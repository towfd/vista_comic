//
//  PendingLookupTests.swift
//  vista_comicTests
//
//  Reporting that a collected word was looked up again (vocabulary-review
//  stage 1, ticket 05).
//
//  Nothing displays this number yet, which makes it easy to under-test. It is
//  worth testing precisely because it cannot be recollected: stages 2 through 4
//  all read it, and a bug here is invisible until one of them is built on top
//  of a column of wrong numbers.
//
//  Two properties carry the ticket. **Repeats must survive** — two lookups mean
//  the reader forgot the same word twice, and any collapsing erases the signal.
//  And **nothing here may ever reach the reader**: they asked for a
//  translation, and bookkeeping behind it is not their problem.
//

import Foundation
import Testing

@testable import vista_comic

private let offline = URLError(.notConnectedToInternet)

/// Records lookups it was asked to send, and can be scripted to fail.
private final class LookupSpyRepository: StudyRepository, @unchecked Sendable {
    var recordLookupResults: [Result<Void, Error>] = [.success(())]
    private(set) var recordedIDs: [Int] = []
    private var callCount = 0

    var updateResult: Result<LearningCard, Error> = .success(.stub())
    private(set) var updatedID: Int?
    private(set) var updatedTranslation: String?
    private(set) var updatedKind: CardKind?
    @discardableResult
    func update(id: Int, translation: String, kind: CardKind?) async throws -> LearningCard {
        updatedID = id
        updatedTranslation = translation
        updatedKind = kind
        return try updateResult.get()
    }

    var deleteResult: Result<Void, Error> = .success(())
    private(set) var deletedID: Int?
    func delete(id: Int) async throws {
        deletedID = id
        try deleteResult.get()
    }

    func recordLookup(id: Int) async throws {
        defer { callCount += 1 }
        let result = recordLookupResults[min(callCount, recordLookupResults.count - 1)]
        // Recorded before the throw, so a failing attempt is still visible as
        // an attempt — otherwise "queued after failing" and "never tried" look
        // the same to a test.
        recordedIDs.append(id)
        try result.get()
    }

    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome { .collected(.stub()) }

    func cards() async throws -> [LearningCard] { [] }
    func knownCards() -> [LearningCard] { [] }
}

@Suite("The pending lookup queue")
struct PendingLookupStoreTests {

    @Test("Two lookups of the same card are two entries")
    func repeatsAreKept() {
        // The whole point. Two lookups mean the reader forgot the same word
        // twice, and collapsing them would erase exactly the signal this
        // exists to capture — unlike the card queue, where two taps are one
        // word.
        let store = InMemoryPendingLookupStore()

        store.enqueue(PendingLookup(cardID: 7))
        store.enqueue(PendingLookup(cardID: 7))

        #expect(store.queued().count == 2)
    }

    @Test("Entries come out oldest first")
    func entriesComeOutOldestFirst() {
        let store = InMemoryPendingLookupStore()
        let base = Date(timeIntervalSince1970: 1_000)

        store.enqueue(PendingLookup(cardID: 3, occurredAt: base.addingTimeInterval(2)))
        store.enqueue(PendingLookup(cardID: 1, occurredAt: base))
        store.enqueue(PendingLookup(cardID: 2, occurredAt: base.addingTimeInterval(1)))

        #expect(store.queued().map(\.cardID) == [1, 2, 3])
    }

    @Test("The queue is bounded, dropping the oldest")
    func theQueueIsBounded() {
        let store = InMemoryPendingLookupStore(limit: 2)
        let base = Date(timeIntervalSince1970: 1_000)

        store.enqueue(PendingLookup(cardID: 1, occurredAt: base))
        store.enqueue(PendingLookup(cardID: 2, occurredAt: base.addingTimeInterval(1)))
        store.enqueue(PendingLookup(cardID: 3, occurredAt: base.addingTimeInterval(2)))

        #expect(store.queued().map(\.cardID) == [2, 3])
    }

    @Test("Removing one entry leaves its twin alone")
    func removingOneLeavesItsTwin() {
        // Two entries for the same card differ only by id, so a remove that
        // matched on `cardID` would silently halve the count.
        let store = InMemoryPendingLookupStore()
        let first = PendingLookup(cardID: 7)
        store.enqueue(first)
        store.enqueue(PendingLookup(cardID: 7))

        store.remove(first.id)

        #expect(store.queued().count == 1)
    }

    @Test("The queue survives being rebuilt over the same directory")
    func theQueueSurvivesRelaunch() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lookups-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FilePendingLookupStore(root: root).enqueue(PendingLookup(cardID: 7))

        #expect(try FilePendingLookupStore(root: root).queued().map(\.cardID) == [7])
    }
}

@Suite("Reporting a re-lookup")
struct RecordLookupTests {

    private func repository(
        _ inner: LookupSpyRepository,
        _ store: any PendingLookupStore = InMemoryPendingLookupStore()
    ) -> OfflineFallbackStudyRepository {
        OfflineFallbackStudyRepository(
            wrapping: inner,
            pending: InMemoryPendingCardStore(),
            pendingLookups: store
        )
    }

    @Test("A reachable backend is told straight away")
    func areachableBackendIsToldStraightAway() async throws {
        let inner = LookupSpyRepository()
        let store = InMemoryPendingLookupStore()

        try await repository(inner, store).recordLookup(id: 42)

        #expect(inner.recordedIDs == [42])
        #expect(store.queued().isEmpty)
    }

    @Test("A report that cannot be sent is kept")
    func areportThatCannotBeSentIsKept() async throws {
        let inner = LookupSpyRepository()
        inner.recordLookupResults = [.failure(offline)]
        let store = InMemoryPendingLookupStore()

        try await repository(inner, store).recordLookup(id: 42)

        #expect(store.queued().map(\.cardID) == [42])
    }

    @Test("Reporting never throws at the reader")
    func reportingNeverThrows() async throws {
        // They asked for a translation and they have it. Bookkeeping behind it
        // is not something to interrupt them with.
        let inner = LookupSpyRepository()
        inner.recordLookupResults = [.failure(offline)]

        try await repository(inner).recordLookup(id: 42)
    }

    @Test("A refused report is dropped rather than kept forever")
    func arefusedReportIsDropped() async throws {
        // 404 means the card is gone from the server. No amount of retrying
        // brings it back, and keeping it would wedge everything behind it.
        let inner = LookupSpyRepository()
        inner.recordLookupResults = [.failure(APIError.httpStatus(404))]
        let store = InMemoryPendingLookupStore()

        try await repository(inner, store).recordLookup(id: 42)

        #expect(store.queued().isEmpty)
    }

    @Test("Reading the deck sends what is waiting")
    func readingTheDeckSendsWhatIsWaiting() async throws {
        let inner = LookupSpyRepository()
        let store = InMemoryPendingLookupStore()
        store.enqueue(PendingLookup(cardID: 9))

        _ = try await repository(inner, store).cards()

        #expect(inner.recordedIDs == [9])
        #expect(store.queued().isEmpty)
    }

    @Test("Two forgettings of one word are both reported")
    func twoForgettingsAreBothReported() async throws {
        let inner = LookupSpyRepository()
        inner.recordLookupResults = [.failure(offline), .failure(offline), .success(())]
        let store = InMemoryPendingLookupStore()
        let repo = repository(inner, store)

        try await repo.recordLookup(id: 7)
        try await repo.recordLookup(id: 7)
        #expect(store.queued().count == 2)

        _ = try await repo.cards()

        #expect(store.queued().isEmpty)
        // Twice on the wire, because the reader forgot it twice.
        #expect(inner.recordedIDs.filter { $0 == 7 }.count == 4)
    }
}

@Suite("Draining the lookup queue")
struct PendingLookupFlusherTests {

    @Test("Entries are sent oldest first and dropped only on success")
    func sentOldestFirstAndDroppedOnlyOnSuccess() async {
        let store = InMemoryPendingLookupStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.enqueue(PendingLookup(cardID: 2, occurredAt: base.addingTimeInterval(1)))
        store.enqueue(PendingLookup(cardID: 1, occurredAt: base))

        let sent = SentIDs()
        await PendingLookupFlusher(store: store) { await sent.record($0.cardID) }.flush()

        #expect(await sent.ids == [1, 2])
        #expect(store.queued().isEmpty)
    }

    @Test("A connection failure stops the flush and keeps everything")
    func aConnectionFailureKeepsEverything() async {
        let store = InMemoryPendingLookupStore()
        store.enqueue(PendingLookup(cardID: 1))
        store.enqueue(PendingLookup(cardID: 2))

        await PendingLookupFlusher(store: store) { _ in throw offline }.flush()

        #expect(store.queued().count == 2)
    }

    @Test("A refused entry is dropped rather than wedging the queue")
    func arefusedEntryIsDropped() async {
        let store = InMemoryPendingLookupStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.enqueue(PendingLookup(cardID: 1, occurredAt: base))
        store.enqueue(PendingLookup(cardID: 2, occurredAt: base.addingTimeInterval(1)))

        let sent = SentIDs()
        await PendingLookupFlusher(store: store) { lookup in
            if lookup.cardID == 1 { throw APIError.httpStatus(404) }
            await sent.record(lookup.cardID)
        }.flush()

        #expect(store.queued().isEmpty)
        #expect(await sent.ids == [2])
    }

    @Test("An empty queue is a no-op")
    func anEmptyQueueIsANoOp() async {
        let sent = SentIDs()
        await PendingLookupFlusher(store: InMemoryPendingLookupStore()) {
            await sent.record($0.cardID)
        }.flush()

        #expect(await sent.ids.isEmpty)
    }
}

private actor SentIDs {
    private(set) var ids: [Int] = []
    func record(_ id: Int) { ids.append(id) }
}
