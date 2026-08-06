//
//  HistoryActionsTests.swift
//  vista_comicTests
//
//  `comprehension-response-ux` ticket 20: what a reader can do *to* a 歷史紀錄
//  record — retry it, delete it, jump back to where it came from — and, just as
//  importantly, which records offer none of those.
//
//  Exercises the free functions the two History screens call, against a stub
//  `ComprehensionRepository`, so nothing here touches the network or renders a
//  view. Mirrors `VocabularyDeleteFlowTests`' shape for the delete flow it
//  replaces. Reuses `ComprehensionRecord.preview(...)`, the same factory the
//  `#Preview`s use, so fixtures and previews cannot drift apart.
//

import Foundation
import Testing

@testable import vista_comic

/// Records what it was asked to do and returns (or throws) what the test tells
/// it to. Only `retry` and `delete` are scripted — the rest of the protocol is
/// satisfied so this conforms, and is not what these tests are about.
private final class StubComprehensionRepository: ComprehensionRepository, @unchecked Sendable {
    struct StubError: Error, Equatable {
        var message: String
    }

    var retryResult: Result<ComprehensionRecord, Error> = .success(.preview(status: "pending"))
    var deleteResult: Result<Void, Error> = .success(())

    private(set) var retryCallCount = 0
    private(set) var lastRetriedID: Int?
    private(set) var deleteCallCount = 0
    private(set) var lastDeletedID: Int?

    func retry(id: Int) async throws -> ComprehensionRecord {
        retryCallCount += 1
        lastRetriedID = id
        return try retryResult.get()
    }

    func delete(id: Int) async throws {
        deleteCallCount += 1
        lastDeletedID = id
        try deleteResult.get()
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

    func list() async throws -> [ComprehensionRecord] { [] }
    func record(id: Int) async throws -> ComprehensionRecord { .preview() }
    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        .preview(isRead: isRead)
    }
}

@Suite("歷史紀錄 → acting on a record")
struct HistoryActionsTests {

    // MARK: - Retry

    /// Retry is a backend re-enqueue, and what comes back is what the screen
    /// shows: the record is being produced again, not merely marked as such
    /// locally.
    @Test func retryReturnsTheRecordToBeingProduced() async throws {
        let stub = StubComprehensionRepository()
        stub.retryResult = .success(.preview(id: 7, status: "pending"))

        let state = await retryComprehensionRecord(id: 7, using: stub)

        guard case .loaded(let requeued) = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(stub.lastRetriedID == 7)
        #expect(stub.retryCallCount == 1)
        #expect(requeued.status == .pending)
        #expect(ComprehensionSectionState(record: requeued) == .inProgress)
    }

    /// A retry that never reached the backend must not read as one that
    /// worked — the record is still failed, and the reader needs telling.
    @Test func retryFailureSurfacesAsFailedNotSilently() async throws {
        let stub = StubComprehensionRepository()
        stub.retryResult = .failure(StubComprehensionRepository.StubError(message: "unreachable"))

        let state = await retryComprehensionRecord(id: 1, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(
            (error as? StubComprehensionRepository.StubError)?.message == "unreachable"
        )
    }

    // MARK: - Who may retry at all

    /// The rule the detail screen applies before offering the button, read off
    /// the section state both it and the reader's result screen share — so the
    /// two screens can never disagree about what is retryable.
    ///
    /// A `declined` record offers none: retrying would spend quota to receive
    /// the same verdict.
    @Test func onlyAFailedRecordOffersRetry() async throws {
        #expect(retryIsOffered(for: .preview(status: "failed")))
        #expect(retryIsOffered(for: .preview(status: "declined")) == false)
        #expect(retryIsOffered(for: .preview(status: "pending")) == false)
        #expect(retryIsOffered(for: .preview(status: "running")) == false)
        #expect(retryIsOffered(for: .preview(status: "ok", notes: "…")) == false)
    }

    /// Same reasoning the row's status line uses: an `ok` record carrying no
    /// notes is a failure, and a failure is retryable — the reader would
    /// otherwise be stuck looking at a heading with nothing under it.
    @Test func okWithoutNotesIsRetryableBecauseItIsAFailure() async throws {
        #expect(retryIsOffered(for: .preview(status: "ok")))
    }

    private func retryIsOffered(for record: ComprehensionRecord) -> Bool {
        guard case .unavailable(let reason) = ComprehensionSectionState(record: record) else {
            return false
        }
        return reason.allowsRetry
    }

    // MARK: - Delete

    @Test func successfulDeleteYieldsLoadedVoid() async throws {
        let stub = StubComprehensionRepository()
        stub.deleteResult = .success(())

        let state = await deleteComprehensionRecord(id: 42, using: stub)

        guard case .loaded = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(stub.lastDeletedID == 42)
        #expect(stub.deleteCallCount == 1)
    }

    /// A failed delete must not be swallowed: the record still exists on the
    /// backend, so the list has to keep the row and say what happened. Deletion
    /// is irreversible and has no undo — a delete that only *looked* like it
    /// worked is the worst of both.
    @Test func deleteFailureSurfacesAsFailedNotSilently() async throws {
        let stub = StubComprehensionRepository()
        stub.deleteResult = .failure(StubComprehensionRepository.StubError(message: "unreachable"))

        let state = await deleteComprehensionRecord(id: 1, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(
            (error as? StubComprehensionRepository.StubError)?.message == "unreachable"
        )
    }

    // MARK: - Jumping back to the source page

    /// The comic is gone from the library, so the route would fail — but the
    /// record itself stays perfectly readable. Only the navigation is withdrawn.
    @Test func aRecordWhoseComicLeftTheLibraryCannotBeJumpedTo() async throws {
        let orphan = ComprehensionRecord.preview(
            status: "ok", notes: "…", comicTitle: nil, chapterTitle: nil
        )

        #expect(orphan.canJumpToSource == false)
        #expect(orphan.displayedTranslation.isEmpty == false)
        #expect(orphan.sourceText.isEmpty == false)
    }

    @Test func aRecordWhoseComicIsStillThereCanBeJumpedTo() async throws {
        #expect(ComprehensionRecord.preview().canJumpToSource)
    }

    /// A comic present with only its chapter title missing still jumps: the
    /// reader route resolves the chapter itself, and the comic is what the
    /// backend's `nil` is actually telling us about.
    @Test func aMissingChapterTitleAloneDoesNotDisableTheJump() async throws {
        #expect(ComprehensionRecord.preview(chapterTitle: nil).canJumpToSource)
    }
}
