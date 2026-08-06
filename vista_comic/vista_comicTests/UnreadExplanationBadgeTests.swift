//
//  UnreadExplanationBadgeTests.swift
//  vista_comicTests
//
//  `comprehension-response-ux` ticket 22: the badge has to learn an explanation
//  arrived while the reader is somewhere else, and then shut up.
//
//  The bug this covers was not in the counting — that was always right — but in
//  when anything asked. So the assertions worth making are about *when the badge
//  goes and looks*: that a watch ends at a terminal status, that it never starts
//  when nothing is in flight, and that watching never marks anything read.
//
//  `sleep` is injected so the poll runs in real time rather than real minutes,
//  the seam `awaitExplanation` already established. No sleeps, no threads.
//

import Foundation
import Testing

@testable import vista_comic

/// Serves a scripted sequence of records and counts what was asked of it.
private final class StubComprehensionRepository: ComprehensionRepository, @unchecked Sendable {
    var listResults: [Result<[ComprehensionRecord], Error>] = [.success([])]
    /// Consumed one per `record(id:)` call; the last entry repeats once
    /// exhausted, so a poll that over-runs cannot crash the test.
    var recordResults: [Result<ComprehensionRecord, Error>] = []

    private(set) var listCallCount = 0
    private(set) var recordCallCount = 0
    private(set) var setReadCallCount = 0

    struct StubError: Error {}

    func list() async throws -> [ComprehensionRecord] {
        defer { listCallCount += 1 }
        return try listResults[min(listCallCount, listResults.count - 1)].get()
    }

    func record(id: Int) async throws -> ComprehensionRecord {
        defer { recordCallCount += 1 }
        guard !recordResults.isEmpty else { throw StubError() }
        return try recordResults[min(recordCallCount, recordResults.count - 1)].get()
    }

    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        setReadCallCount += 1
        return .preview(isRead: isRead)
    }

    func enqueue(
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        useStrongerModel: Bool
    ) async throws -> ComprehensionRecord { .preview() }

    func retry(id: Int) async throws -> ComprehensionRecord { .preview() }
    func delete(id: Int) async throws {}
}

@MainActor
@Suite("The 歷史紀錄 badge")
struct UnreadExplanationBadgeTests {

    /// A badge that never sleeps, so a poll costs no wall-clock time.
    private func makeBadge() -> UnreadExplanationBadge {
        UnreadExplanationBadge(pollInterval: .zero, sleep: { _ in })
    }

    /// Waits for the badge's unstructured watch task to finish.
    ///
    /// Real (tiny) suspensions rather than `Task.yield()`: the watch is its own
    /// task, and yielding from this one does not reliably hand it enough turns
    /// to get through several poll iterations. Bounded at ~2s so a watch that
    /// never stops fails the test instead of hanging the suite — which is
    /// exactly the regression worth catching.
    private func settle(
        _ badge: UnreadExplanationBadge,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<2000 {
            guard badge.isWatching else { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the watch never stopped", sourceLocation: sourceLocation)
    }

    // MARK: - Counting

    @Test func itCountsOnlyArrivedUnreadExplanations() async throws {
        let badge = makeBadge()

        badge.recount(from: [
            .preview(id: 1, status: "ok", notes: "…", isRead: false),  // counts
            .preview(id: 2, status: "ok", notes: "…", isRead: true),   // already read
            .preview(id: 3, status: "pending"),                         // still coming
            .preview(id: 4, status: "failed"),                          // dead end
        ])

        #expect(badge.count == 1)
    }

    @Test func aRefreshCountsWhateverTheBackendHas() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.listResults = [.success([
            .preview(id: 1, status: "ok", notes: "…", isRead: false),
            .preview(id: 2, status: "ok", notes: "…", isRead: false),
        ])]

        await badge.refresh(using: stub)

        #expect(badge.count == 2)
    }

    /// "We couldn't ask" is not "nothing is waiting". A badge that zeroed itself
    /// on a dropped connection would quietly retract a reminder the reader still
    /// needs — the same rule that stops the list showing a read failure as an
    /// empty history.
    @Test func aFailedRefreshLeavesThePreviousCountStanding() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.listResults = [
            .success([.preview(id: 1, status: "ok", notes: "…", isRead: false)]),
            .failure(StubComprehensionRepository.StubError()),
        ]

        await badge.refresh(using: stub)
        await badge.refresh(using: stub)

        #expect(badge.count == 1)
    }

    // MARK: - Watching, which is the actual bug

    /// The reported bug: translate, dismiss the sheet, keep reading. Nothing was
    /// fetching, so the badge stayed silent until the reader opened the tab it
    /// was supposed to send them to.
    @Test func anExplanationLandingWhileTheReaderIsElsewhereRaisesTheBadge() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        let enqueued = ComprehensionRecord.preview(id: 7, status: "pending")
        stub.recordResults = [
            .success(.preview(id: 7, status: "pending")),
            .success(.preview(id: 7, status: "running")),
            .success(.preview(id: 7, status: "ok", notes: "…", isRead: false)),
        ]
        stub.listResults = [
            .success([.preview(id: 7, status: "ok", notes: "…", isRead: false)])
        ]

        badge.watch(enqueued, using: stub)
        await settle(badge)

        #expect(badge.count == 1)
    }

    /// Watching means the reader is *not* looking. Marking read here would erase
    /// the very reminder the watch exists to raise.
    @Test func watchingNeverMarksAnythingRead() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.recordResults = [.success(.preview(id: 7, status: "ok", notes: "…"))]

        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        await settle(badge)

        #expect(stub.setReadCallCount == 0)
    }

    /// The poll must end at a terminal status, or it runs for the life of the
    /// app against a record that will never change again.
    @Test func theWatchStopsOnceTheRecordIsFinished() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.recordResults = [.success(.preview(id: 7, status: "ok", notes: "…"))]

        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        await settle(badge)

        #expect(badge.isWatching == false)
        // One look was enough: it was already finished when first asked.
        #expect(stub.recordCallCount == 1)
    }

    /// A record that already reached a terminal status is not in flight, so
    /// there is nothing to wait for — the mechanism must stay silent rather than
    /// spend a request confirming what it was just told.
    @Test func nothingInFlightMeansNoPollingAtAll() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()

        badge.watch(.preview(id: 7, status: "ok", notes: "…"), using: stub)
        await settle(badge)

        #expect(badge.isWatching == false)
        #expect(stub.recordCallCount == 0)
        #expect(stub.listCallCount == 0)
    }

    /// The result screen announces its record on translate and again on retry,
    /// and a reader may re-enter the same one. One id, one loop.
    @Test func watchingTheSameRecordTwiceStartsOnlyOneLoop() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.recordResults = [.success(.preview(id: 7, status: "ok", notes: "…"))]

        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        await settle(badge)

        #expect(stub.recordCallCount == 1)
    }

    /// A transient failure mid-wait must not end the poll — a dropped
    /// connection while the reader carries on reading is exactly the case worth
    /// surviving.
    @Test func aFailedPollKeepsWaitingRatherThanGivingUp() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.recordResults = [
            .failure(StubComprehensionRepository.StubError()),
            .failure(StubComprehensionRepository.StubError()),
            .success(.preview(id: 7, status: "ok", notes: "…", isRead: false)),
        ]
        stub.listResults = [
            .success([.preview(id: 7, status: "ok", notes: "…", isRead: false)])
        ]

        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        await settle(badge)

        #expect(badge.count == 1)
        #expect(stub.recordCallCount == 3)
    }

    /// An explanation the reader watched land was marked read on the result
    /// screen, so the badge's own recount must not raise it again.
    @Test func oneTheReaderAlreadyWatchedLandDoesNotBadge() async throws {
        let badge = makeBadge()
        let stub = StubComprehensionRepository()
        stub.recordResults = [.success(.preview(id: 7, status: "ok", notes: "…", isRead: true))]
        stub.listResults = [
            .success([.preview(id: 7, status: "ok", notes: "…", isRead: true)])
        ]

        badge.watch(.preview(id: 7, status: "pending"), using: stub)
        await settle(badge)

        #expect(badge.count == 0)
    }
}
