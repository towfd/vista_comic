//
//  PendingCardTests.swift
//  vista_comicTests
//
//  Collecting with no connection (vocabulary-review stage 1, ticket 04).
//
//  The behaviour that matters here is what survives: a word the reader
//  deliberately picked on a train has to still be theirs when they land, and it
//  has to arrive exactly once. Everything else in this file is a guard on the
//  ways a queue can quietly lose or duplicate things.
//

import Foundation
import Testing

@testable import vista_comic

/// A `StudyRepository` whose every call can be scripted, and which records what
/// it was offered so the flush order can be asserted.
private final class ScriptedStudyRepository: StudyRepository, @unchecked Sendable {
    /// Consumed one per `collect` call; the last entry repeats once exhausted so
    /// an over-running flush does not crash.
    var collectResults: [Result<CollectOutcome, Error>] = [.success(.collected(.stub()))]
    private(set) var collectCallCount = 0
    private(set) var offeredSourceTexts: [String] = []

    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome {
        defer { collectCallCount += 1 }
        offeredSourceTexts.append(sourceText)
        return try collectResults[min(collectCallCount, collectResults.count - 1)].get()
    }

    var cardsResult: Result<[LearningCard], Error> = .success([])
    private(set) var cardsCallCount = 0
    func cards() async throws -> [LearningCard] {
        cardsCallCount += 1
        return try cardsResult.get()
    }

    func recordLookup(id: Int) async throws {}
    func knownCards() -> [LearningCard] { [] }
}

private func pendingCard(
    _ sourceText: String,
    queuedAt: Date = Date(),
    targetLanguage: String = "zh-Hant"
) -> PendingCard {
    PendingCard(
        sourceText: sourceText,
        translation: "…",
        targetLanguage: targetLanguage,
        comicID: "comic-1",
        chapterID: "chapter-1",
        pageNumber: 1,
        queuedAt: queuedAt
    )
}

private let offline = URLError(.notConnectedToInternet)

@Suite("The pending card queue")
struct PendingCardStoreTests {

    @Test("A queued line comes back out")
    func aQueuedLineComesBackOut() {
        let store = InMemoryPendingCardStore()

        store.enqueue(pendingCard("大丈夫ですか"))

        #expect(store.queued().map(\.sourceText) == ["大丈夫ですか"])
    }

    @Test("The same line queued twice is one entry")
    func theSameLineTwiceIsOneEntry() {
        // A double tap while offline is one word, not two — and the identity
        // that decides it is the same one the backend enforces.
        let store = InMemoryPendingCardStore()

        store.enqueue(pendingCard("大丈夫ですか"))
        store.enqueue(pendingCard("大丈夫\nですか"))

        #expect(store.queued().count == 1)
    }

    @Test("The same word for another language is a separate entry")
    func anotherLanguageIsASeparateEntry() {
        let store = InMemoryPendingCardStore()

        store.enqueue(pendingCard("大丈夫ですか"))
        store.enqueue(pendingCard("大丈夫ですか", targetLanguage: "en"))

        #expect(store.queued().count == 2)
    }

    @Test("The first queuing wins, so the time reflects when it was chosen")
    func theFirstQueuingWins() {
        let early = Date(timeIntervalSince1970: 1_000)
        let store = InMemoryPendingCardStore()

        store.enqueue(pendingCard("大丈夫ですか", queuedAt: early))
        store.enqueue(pendingCard("大丈夫ですか", queuedAt: early.addingTimeInterval(500)))

        #expect(store.queued().first?.queuedAt == early)
    }

    @Test("Entries come out oldest first")
    func entriesComeOutOldestFirst() {
        let store = InMemoryPendingCardStore()
        let base = Date(timeIntervalSince1970: 1_000)

        store.enqueue(pendingCard("third", queuedAt: base.addingTimeInterval(2)))
        store.enqueue(pendingCard("first", queuedAt: base))
        store.enqueue(pendingCard("second", queuedAt: base.addingTimeInterval(1)))

        #expect(store.queued().map(\.sourceText) == ["first", "second", "third"])
    }

    @Test("The queue is bounded, and the oldest goes first")
    func theQueueIsBounded() {
        // Storage the reader never asked for and cannot see must not be able to
        // grow without a limit.
        let store = InMemoryPendingCardStore(limit: 2)
        let base = Date(timeIntervalSince1970: 1_000)

        store.enqueue(pendingCard("oldest", queuedAt: base))
        store.enqueue(pendingCard("middle", queuedAt: base.addingTimeInterval(1)))
        store.enqueue(pendingCard("newest", queuedAt: base.addingTimeInterval(2)))

        #expect(store.queued().map(\.sourceText) == ["middle", "newest"])
    }

    @Test("The queue survives being rebuilt over the same directory")
    func theQueueSurvivesRelaunch() throws {
        // What closing the app on the plane and reopening it does.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cards-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FilePendingCardStore(root: root).enqueue(pendingCard("大丈夫ですか"))

        #expect(try FilePendingCardStore(root: root).queued().count == 1)
    }

    @Test("Removing takes the entry out and leaves the rest")
    func removingTakesOneEntryOut() {
        let store = InMemoryPendingCardStore()
        let kept = pendingCard("kept")
        store.enqueue(pendingCard("sent"))
        store.enqueue(kept)

        store.remove(pendingCard("sent").identity)

        #expect(store.queued().map(\.sourceText) == ["kept"])
    }
}

@Suite("Collecting with no connection")
struct OfflineCollectTests {

    private func repository(
        _ inner: ScriptedStudyRepository,
        _ store: any PendingCardStore = InMemoryPendingCardStore()
    ) -> OfflineFallbackStudyRepository {
        OfflineFallbackStudyRepository(wrapping: inner, pending: store)
    }

    private func collect(
        _ repository: OfflineFallbackStudyRepository,
        _ sourceText: String = "大丈夫ですか",
        kind: CardKind = .word
    ) async throws -> CollectOutcome {
        try await repository.collect(
            sourceText: sourceText,
            translation: "你還好嗎",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1,
            kind: kind
        )
    }

    @Test("A word that cannot be sent is kept, not lost")
    func anUnsendableWordIsKept() async throws {
        let inner = ScriptedStudyRepository()
        inner.collectResults = [.failure(offline)]
        let store = InMemoryPendingCardStore()

        let outcome = try await collect(repository(inner, store))

        #expect(outcome == .queued)
        #expect(store.queued().map(\.sourceText) == ["大丈夫ですか"])
    }

    @Test("Collecting offline never throws at the reader")
    func collectingOfflineNeverThrows() async throws {
        // They are in the middle of reading a comic. A missing connection is
        // not something to interrupt them about.
        let inner = ScriptedStudyRepository()
        inner.collectResults = [.failure(offline)]

        _ = try await collect(repository(inner))
    }

    @Test("A refusal is reported rather than queued")
    func aRefusalIsReported() async {
        // 4xx is not a connection problem. Queueing it would only mean offering
        // the server the same thing until the flush drops it anyway.
        let inner = ScriptedStudyRepository()
        inner.collectResults = [.failure(APIError.httpStatus(422))]
        let store = InMemoryPendingCardStore()

        await #expect(throws: APIError.self) {
            _ = try await collect(repository(inner, store))
        }
        #expect(store.queued().isEmpty)
    }

    @Test("A queued line is recognised as already collected")
    func aQueuedLineIsRecognised() async throws {
        let inner = ScriptedStudyRepository()
        inner.collectResults = [.failure(offline)]
        let repo = repository(inner)

        _ = try await collect(repo)

        #expect(queuedEntry(for: "大丈夫ですか", targetLanguage: "zh-Hant", in: repo.queuedLines()) != nil)
        // Still not a *card*: the server has issued no id, so nothing can be
        // reported against it.
        #expect(repo.knownCards().isEmpty)
    }

    @Test("A successful collect flushes what was waiting")
    func aSuccessfulCollectFlushesTheQueue() async throws {
        // A success is the proof the network is back — the cheapest flush
        // trigger there is.
        let inner = ScriptedStudyRepository()
        let store = InMemoryPendingCardStore()
        store.enqueue(pendingCard("waiting", queuedAt: Date(timeIntervalSince1970: 1)))

        _ = try await collect(repository(inner, store))

        #expect(store.queued().isEmpty)
        #expect(inner.offeredSourceTexts.contains("waiting"))
    }

    @Test("Reading the deck sends what is waiting first")
    func readingTheDeckFlushesFirst() async throws {
        // Before, not after: this response becomes the snapshot the marker
        // reads, and one taken before the queue drained would be missing
        // exactly the words collected most recently.
        let inner = ScriptedStudyRepository()
        let store = InMemoryPendingCardStore()
        store.enqueue(pendingCard("waiting"))

        _ = try await repository(inner, store).cards()

        #expect(store.queued().isEmpty)
    }
}

@Suite("Draining the queue")
struct PendingCardFlusherTests {

    @Test("Entries are sent oldest first")
    func entriesAreSentOldestFirst() async {
        let store = InMemoryPendingCardStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.enqueue(pendingCard("second", queuedAt: base.addingTimeInterval(1)))
        store.enqueue(pendingCard("first", queuedAt: base))

        let sent = Sent()
        await PendingCardFlusher(store: store) { await sent.record($0.sourceText) }.flush()

        #expect(await sent.texts == ["first", "second"])
        #expect(store.queued().isEmpty)
    }

    @Test("An entry is dropped only once the server has taken it")
    func anEntryIsDroppedOnlyOnSuccess() async {
        let store = InMemoryPendingCardStore()
        store.enqueue(pendingCard("大丈夫ですか"))

        await PendingCardFlusher(store: store) { _ in throw offline }.flush()

        #expect(store.queued().count == 1)
    }

    @Test("A refused entry is dropped rather than wedging the queue")
    func aRefusedEntryIsDropped() async {
        // Left at the head, it would hold every later word behind it forever.
        // The reader loses one word instead of all of them.
        let store = InMemoryPendingCardStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.enqueue(pendingCard("refused", queuedAt: base))
        store.enqueue(pendingCard("fine", queuedAt: base.addingTimeInterval(1)))

        let sent = Sent()
        await PendingCardFlusher(store: store) { card in
            if card.sourceText == "refused" { throw APIError.httpStatus(422) }
            await sent.record(card.sourceText)
        }.flush()

        #expect(store.queued().isEmpty)
        #expect(await sent.texts == ["fine"])
    }

    @Test("A connection failure stops the flush and leaves the rest queued")
    func aConnectionFailureStopsTheFlush() async {
        let store = InMemoryPendingCardStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.enqueue(pendingCard("first", queuedAt: base))
        store.enqueue(pendingCard("second", queuedAt: base.addingTimeInterval(1)))

        let sent = Sent()
        await PendingCardFlusher(store: store) { card in
            if card.sourceText == "first" { throw offline }
            await sent.record(card.sourceText)
        }.flush()

        #expect(store.queued().count == 2)
        #expect(await sent.texts.isEmpty)
    }

    @Test("An empty queue is a no-op")
    func anEmptyQueueIsANoOp() async {
        let sent = Sent()
        await PendingCardFlusher(store: InMemoryPendingCardStore()) {
            await sent.record($0.sourceText)
        }.flush()

        #expect(await sent.texts.isEmpty)
    }
}

/// Collects what the flusher sent, from whatever context it ran in.
private actor Sent {
    private(set) var texts: [String] = []
    func record(_ text: String) { texts.append(text) }
}


@Suite("A queued line remembers which button was pressed")
struct QueuedKindTests {

    @Test("The kind survives being queued", arguments: CardKind.allCases)
    func theKindSurvivesBeingQueued(_ kind: CardKind) async throws {
        let inner = ScriptedStudyRepository()
        inner.collectResults = [.failure(offline)]
        let repo = OfflineFallbackStudyRepository(
            wrapping: inner, pending: InMemoryPendingCardStore()
        )

        _ = try await repo.collect(
            sourceText: "大丈夫ですか",
            translation: "你還好嗎",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1,
            kind: kind
        )

        let queued = queuedEntry(
            for: "大丈夫ですか", targetLanguage: "zh-Hant", in: repo.queuedLines()
        )
        #expect(queued?.kind == kind)
    }

    @Test("A queue written before kinds existed still decodes")
    func anOlderQueueStillDecodes() throws {
        // The field is optional precisely so a queue file from a previous build
        // does not take the reader's offline words down with it.
        let older = Data("""
        [{"sourceText":"大丈夫ですか","translation":"你還好嗎","targetLanguage":"zh-Hant",
          "comicID":"c","chapterID":"ch","pageNumber":1,"queuedAt":0}]
        """.utf8)

        let decoded = try JSONDecoder().decode([PendingCard].self, from: older)

        #expect(decoded.count == 1)
        #expect(decoded.first?.kind == nil)
    }
}
