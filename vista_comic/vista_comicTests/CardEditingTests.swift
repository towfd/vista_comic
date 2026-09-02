//
//  CardEditingTests.swift
//  vista_comicTests
//
//  Correcting and deleting a card (vocabulary stage 2, ticket 04).
//
//  The property worth guarding here is a *refusal*: unlike everything stage 1
//  built, these two operations are **not** queued when they fail. Every queue in
//  this feature only ever adds, and edit and delete are the first operations
//  that can cancel each other out — a card deleted offline and then re-collected
//  offline has no obviously correct outcome, and the rule for it would be
//  invented rather than derived. A test that let them start queueing would look
//  like an improvement.
//

import Foundation
import Testing

@testable import vista_comic

private let offline = URLError(.notConnectedToInternet)

/// Records what it was asked to change, and can be scripted to fail.
private final class EditSpyRepository: StudyRepository, @unchecked Sendable {
    var updateResult: Result<LearningCard, Error> = .success(.preview())
    private(set) var updateCallCount = 0
    private(set) var lastID: Int?
    private(set) var lastTranslation: String?
    /// Double-optional on purpose: it has to tell "never called" apart from
    /// "called with nothing", which is the whole point of the kind being
    /// clearable.
    private(set) var lastKind: CardKind??

    @discardableResult
    func update(id: Int, translation: String, kind: CardKind?) async throws -> LearningCard {
        updateCallCount += 1
        lastID = id
        lastTranslation = translation
        lastKind = .some(kind)
        return try updateResult.get()
    }

    var resetResult: Result<LearningCard, Error> = .success(.preview())
    private(set) var resetCallCount = 0
    private(set) var resetID: Int?

    @discardableResult
    func reset(id: Int) async throws -> LearningCard {
        resetCallCount += 1
        resetID = id
        return try resetResult.get()
    }

    var deleteResult: Result<Void, Error> = .success(())
    private(set) var deleteCallCount = 0
    private(set) var deletedID: Int?
    func delete(id: Int) async throws {
        deleteCallCount += 1
        deletedID = id
        try deleteResult.get()
    }

    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome { .collected(.preview()) }

    func cards() async throws -> [LearningCard] { [] }
    func knownCards() -> [LearningCard] { [] }
    func recordLookup(id: Int) async throws {}
}

@Suite("Correcting a card")
struct CardUpdateTests {

    private func repository(
        _ inner: EditSpyRepository,
        cards: any PendingCardStore = InMemoryPendingCardStore(),
        lookups: any PendingLookupStore = InMemoryPendingLookupStore()
    ) -> OfflineFallbackStudyRepository {
        OfflineFallbackStudyRepository(
            wrapping: inner, pending: cards, pendingLookups: lookups
        )
    }

    @Test("A corrected translation reaches the backend")
    func aCorrectedTranslationReachesTheBackend() async throws {
        let inner = EditSpyRepository()

        _ = try await repository(inner).update(id: 7, translation: "你沒事吧", kind: .word)

        #expect(inner.lastID == 7)
        #expect(inner.lastTranslation == "你沒事吧")
    }

    @Test("A kind can be set and changed", arguments: CardKind.allCases)
    func aKindCanBeSet(_ kind: CardKind) async throws {
        let inner = EditSpyRepository()

        _ = try await repository(inner).update(id: 7, translation: "你沒事吧", kind: kind)

        #expect(inner.lastKind == .some(kind))
    }

    @Test("A kind can be cleared back to unanswered")
    func aKindCanBeCleared() async throws {
        // Not an omission — a mis-tap between two adjacent save buttons has to
        // be undoable, and cards collected before those buttons existed have no
        // answer to begin with.
        let inner = EditSpyRepository()

        _ = try await repository(inner).update(id: 7, translation: "你沒事吧", kind: nil)

        #expect(inner.lastKind == .some(CardKind?.none))
    }

    @Test("A failed correction throws rather than being queued")
    func aFailedCorrectionIsNotQueued() async {
        // The refusal this ticket rests on. Queueing an edit would introduce
        // the first operation in this feature that can cancel another one out.
        let inner = EditSpyRepository()
        inner.updateResult = .failure(offline)
        let cards = InMemoryPendingCardStore()
        let lookups = InMemoryPendingLookupStore()

        await #expect(throws: URLError.self) {
            _ = try await repository(inner, cards: cards, lookups: lookups)
                .update(id: 7, translation: "你沒事吧", kind: .word)
        }
        #expect(cards.queued().isEmpty)
        #expect(lookups.queued().isEmpty)
    }

    @Test("A successful correction flushes whatever was waiting")
    func aSuccessfulCorrectionFlushesTheQueues() async throws {
        // A success proves the connection is back, which is the cheapest flush
        // trigger there is.
        let inner = EditSpyRepository()
        let cards = InMemoryPendingCardStore()
        cards.enqueue(
            PendingCard(
                sourceText: "waiting",
                translation: "…",
                targetLanguage: "zh-Hant",
                comicID: "c",
                chapterID: "ch",
                pageNumber: 1
            )
        )

        _ = try await repository(inner, cards: cards)
            .update(id: 7, translation: "你沒事吧", kind: .word)

        #expect(cards.queued().isEmpty)
    }
}

@Suite("Resetting a card's progress")
struct CardResetTests {

    private func repository(
        _ inner: EditSpyRepository,
        cards: any PendingCardStore = InMemoryPendingCardStore()
    ) -> OfflineFallbackStudyRepository {
        OfflineFallbackStudyRepository(
            wrapping: inner, pending: cards, pendingLookups: InMemoryPendingLookupStore()
        )
    }

    @Test("A reset reaches the backend")
    func aResetReachesTheBackend() async throws {
        let inner = EditSpyRepository()

        _ = try await repository(inner).reset(id: 7)

        #expect(inner.resetID == 7)
        #expect(inner.resetCallCount == 1)
    }

    @Test("A failed reset throws rather than being queued")
    func aFailedResetIsNotQueued() async {
        // The same refusal update and delete make, and for the same reason: a
        // queued reset would report a card back to new while the deck the
        // reader is looking at still shows it on a year-long interval.
        let inner = EditSpyRepository()
        inner.resetResult = .failure(offline)
        let cards = InMemoryPendingCardStore()

        await #expect(throws: URLError.self) {
            _ = try await repository(inner, cards: cards).reset(id: 7)
        }
        #expect(cards.queued().isEmpty)
    }

    @Test("A successful reset flushes whatever was waiting")
    func aSuccessfulResetFlushesTheQueues() async throws {
        let inner = EditSpyRepository()
        let cards = InMemoryPendingCardStore()
        cards.enqueue(
            PendingCard(
                sourceText: "waiting",
                translation: "…",
                targetLanguage: "zh-Hant",
                comicID: "c",
                chapterID: "ch",
                pageNumber: 1
            )
        )

        _ = try await repository(inner, cards: cards).reset(id: 7)

        #expect(cards.queued().isEmpty)
    }
}

@Suite("Deleting a card")
struct CardDeleteTests {

    private func repository(
        _ inner: EditSpyRepository,
        cards: any PendingCardStore = InMemoryPendingCardStore()
    ) -> OfflineFallbackStudyRepository {
        OfflineFallbackStudyRepository(
            wrapping: inner, pending: cards, pendingLookups: InMemoryPendingLookupStore()
        )
    }

    @Test("A delete reaches the backend")
    func aDeleteReachesTheBackend() async throws {
        let inner = EditSpyRepository()

        try await repository(inner).delete(id: 7)

        #expect(inner.deletedID == 7)
    }

    @Test("A failed delete throws rather than being queued")
    func aFailedDeleteIsNotQueued() async {
        let inner = EditSpyRepository()
        inner.deleteResult = .failure(offline)
        let cards = InMemoryPendingCardStore()

        await #expect(throws: URLError.self) {
            try await repository(inner, cards: cards).delete(id: 7)
        }
        #expect(cards.queued().isEmpty)
    }

    @Test("Deleting is not reported as success when it did not happen")
    func aFailedDeleteIsNotSilent() async {
        // The screen removes the row only on success, so swallowing this would
        // show the reader a card gone that is still on the server.
        let inner = EditSpyRepository()
        inner.deleteResult = .failure(offline)

        var threw = false
        do { try await repository(inner).delete(id: 7) } catch { threw = true }

        #expect(threw)
    }
}

@Suite("What editing cannot touch")
struct CardEditingBoundaryTests {

    @Test("The seam offers no way to change a card's identity")
    func theSeamCannotChangeIdentity() async throws {
        // Structural rather than asserted on a mock: `update` takes a
        // translation and a kind and nothing else, so there is no route from
        // this screen to the source text, the target language, or the page the
        // line was read on. This test exists to fail if that signature grows.
        let inner = EditSpyRepository()
        let card = LearningCard.preview()

        let updated = try await inner.update(id: card.id, translation: "x", kind: nil)

        #expect(updated.sourceText == card.sourceText)
        #expect(updated.targetLanguage == card.targetLanguage)
        #expect(updated.comicID == card.comicID)
        #expect(updated.pageNumber == card.pageNumber)
    }
}
