//
//  OfflineFallbackStudyRepository.swift
//  vista_comic
//
//  Makes collecting work with no connection, by decorating the live
//  `StudyRepository` — the shape `OfflineFallbackComicRepository` established
//  for the catalog.
//
//  The whole of the offline story lives here, so `APIStudyRepository` stays a
//  plain description of the backend's routes and every screen keeps depending
//  on one seam rather than learning where its answers came from.
//

import Foundation

/// A `StudyRepository` that keeps what it could not send.
struct OfflineFallbackStudyRepository: StudyRepository {
    private let inner: any StudyRepository
    private let pending: any PendingCardStore
    private let pendingLookups: any PendingLookupStore
    private let flusher: PendingCardFlusher
    private let lookupFlusher: PendingLookupFlusher

    init(
        wrapping inner: any StudyRepository = APIStudyRepository(),
        pending: any PendingCardStore = InMemoryPendingCardStore(),
        pendingLookups: any PendingLookupStore = InMemoryPendingLookupStore()
    ) {
        self.inner = inner
        self.pending = pending
        self.pendingLookups = pendingLookups
        self.lookupFlusher = PendingLookupFlusher(store: pendingLookups) { lookup in
            try await inner.recordLookup(id: lookup.cardID)
        }
        self.flusher = PendingCardFlusher(store: pending) { card in
            _ = try await inner.collect(
                sourceText: card.sourceText,
                translation: card.translation,
                targetLanguage: card.targetLanguage,
                comicID: card.comicID,
                chapterID: card.chapterID,
                pageNumber: card.pageNumber,
                kind: card.kind
            )
        }
    }

    /// Collects the line, or keeps it until the backend can be reached.
    ///
    /// A failure here is overwhelmingly a missing connection, and the reader is
    /// in the middle of reading a comic — so this does not throw at them. What
    /// they chose is kept, the button says so, and the queue delivers it later.
    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome {
        do {
            let outcome = try await inner.collect(
                sourceText: sourceText,
                translation: translation,
                targetLanguage: targetLanguage,
                comicID: comicID,
                chapterID: chapterID,
                pageNumber: pageNumber,
                kind: kind
            )
            // A success is the proof the network is back, which is the cheapest
            // flush trigger there is — the same trick
            // `OfflineFallbackComicRepository` uses.
            await flusher.flush()
            await lookupFlusher.flush()
            return outcome
        } catch {
            // A refusal is not a connection problem, and queueing it would only
            // mean offering the server the same thing until the queue is
            // drained by the 4xx rule anyway. Told plainly instead.
            if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                throw error
            }
            pending.enqueue(
                PendingCard(
                    sourceText: sourceText,
                    translation: translation,
                    targetLanguage: targetLanguage,
                    comicID: comicID,
                    chapterID: chapterID,
                    pageNumber: pageNumber,
                    kind: kind
                )
            )
            return .queued
        }
    }

    /// Sends whatever is waiting first, then answers.
    ///
    /// **Before, not after**, for the same reason the progress decorator flushes
    /// before its three reads: this response becomes the deck snapshot the
    /// already-collected marker reads, and a snapshot taken before the queue
    /// drained would be missing exactly the words the reader collected most
    /// recently. It costs nothing when the queue is empty, and when the reader
    /// is still offline it costs one request that fails the way this one is
    /// about to anyway.
    func cards() async throws -> [LearningCard] {
        await flusher.flush()
        // Cards first: a lookup can only be reported against a card the server
        // already has, so draining the card queue first is what gives the
        // lookups something to land on.
        await lookupFlusher.flush()
        return try await inner.cards()
    }

    /// Passed straight through, and **not queued** on failure.
    ///
    /// A round needs the backend, as stage 3's did. Queueing answers would mean
    /// replaying them later against a ladder that has since moved — and the
    /// once-a-day rule makes the order they arrive in load-bearing, which a
    /// queue cannot promise.
    @discardableResult
    func recordReview(
        cardID: Int,
        questionType: ReviewQuestionType,
        isCorrect: Bool,
        clientToken: String,
        localDate: Date,
        answeredAt: Date,
        context: ReviewContext,
        elapsedMs: Int?
    ) async throws -> ReviewOutcome {
        try await inner.recordReview(
            cardID: cardID,
            questionType: questionType,
            isCorrect: isCorrect,
            clientToken: clientToken,
            localDate: localDate,
            answeredAt: answeredAt,
            context: context,
            elapsedMs: elapsedMs
        )
    }

    /// Passed straight through, both ways. Practising offline is ticket 07; a
    /// settings edit stays online-only for good, since an offline edit has no
    /// derivable merge rule — the same argument this decorator already makes
    /// about editing a card.
    func settings() async throws -> StudySettings {
        try await inner.settings()
    }

    @discardableResult
    func updateSettings(_ settings: StudySettings) async throws -> StudySettings {
        try await inner.updateSettings(settings)
    }

    /// Notes a re-lookup, keeping it if the backend cannot be reached.
    ///
    /// **Never throws.** The reader is looking at a translation they asked for;
    /// a bookkeeping call failing behind it is not their problem, and there is
    /// nothing they could do about it. A refusal is dropped for the same reason
    /// the flusher drops one — the card is gone from the server, and no amount
    /// of retrying will change that.
    /// Passed straight through, and **not queued** when it fails.
    ///
    /// Everything this decorator queues only ever *adds*. Editing and deleting
    /// are the first operations that can cancel each other out — a card deleted
    /// with no connection and then re-collected with no connection has no
    /// obviously correct outcome, and the rule for it would be invented rather
    /// than derived.
    ///
    /// What that gives up is correcting a translation on a plane, which does
    /// not happen: noticing a bad translation happens while reading, and
    /// reading a downloaded chapter is exactly when the reader is not also
    /// proofreading their deck.
    @discardableResult
    func update(
        id: Int,
        translation: String,
        kind: CardKind?
    ) async throws -> LearningCard {
        let card = try await inner.update(id: id, translation: translation, kind: kind)
        // A success proves the connection is back, so anything waiting can go.
        await flusher.flush()
        await lookupFlusher.flush()
        return card
    }

    /// Passed straight through, for the same reason as `update`.
    func delete(id: Int) async throws {
        try await inner.delete(id: id)
        await flusher.flush()
        await lookupFlusher.flush()
    }

    func recordLookup(id: Int) async throws {
        do {
            try await inner.recordLookup(id: id)
            await lookupFlusher.flush()
        } catch {
            if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                return
            }
            pendingLookups.enqueue(PendingLookup(cardID: id))
        }
    }

    /// Re-lookups the server has not been told about yet. Exposed for tests and
    /// for whatever stage 2 wants to say about them.
    func queuedLookups() -> [PendingLookup] {
        pendingLookups.queued()
    }

    func knownCards() -> [LearningCard] {
        inner.knownCards()
    }

    /// Lines the reader has collected that the server has not seen yet.
    ///
    /// Kept separate from `knownCards()` rather than merged into it, because a
    /// queued line genuinely is not a card: it has no id, so nothing can be
    /// reported against it and nothing can schedule it. Synthesising one would
    /// mean inventing an id the backend never issued.
    func queuedLines() -> [PendingCard] {
        pending.queued()
    }
}

// MARK: - Sending what is queued

/// Drains `PendingCardStore`, one entry at a time, never twice at once.
///
/// An actor because "am I already flushing?" is the only state it has, and two
/// flushes racing would offer the same line twice.
actor PendingCardFlusher {
    private let store: any PendingCardStore
    private let send: @Sendable (PendingCard) async throws -> Void
    private var isFlushing = false

    init(
        store: any PendingCardStore,
        send: @escaping @Sendable (PendingCard) async throws -> Void
    ) {
        self.store = store
        self.send = send
    }

    /// Sends everything waiting, oldest first, dropping each entry **only**
    /// once the server has taken it.
    ///
    /// Stops at the first entry that cannot be sent rather than working through
    /// the rest: the overwhelmingly likely reason is that the connection is
    /// still not there, and the queue exists precisely so nothing has to be
    /// hurried.
    ///
    /// The exception is a server that *refuses* an entry — text it will never
    /// accept, say. That will never be taken however many times it is offered,
    /// and leaving it at the head would wedge every later word behind it
    /// forever, so it is dropped and the flush carries on. The reader loses one
    /// word rather than all of them.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        for entry in store.queued() {
            do {
                try await send(entry)
                store.remove(entry.identity)
            } catch {
                if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                    store.remove(entry.identity)
                    continue
                }
                return
            }
        }
    }
}


/// Drains `PendingLookupStore`, one entry at a time, never twice at once.
///
/// The same discipline as `PendingCardFlusher`, and deliberately a second actor
/// rather than a generic one: `PendingProgressFlusher` already established that
/// each queue owns its own drainer, and the shared shape is four lines of
/// control flow whose meaning is entirely in what it is draining.
actor PendingLookupFlusher {
    private let store: any PendingLookupStore
    private let send: @Sendable (PendingLookup) async throws -> Void
    private var isFlushing = false

    init(
        store: any PendingLookupStore,
        send: @escaping @Sendable (PendingLookup) async throws -> Void
    ) {
        self.store = store
        self.send = send
    }

    /// Sends everything waiting, oldest first, dropping each entry **only**
    /// once the server has taken it — or when the server refuses it, which for
    /// a lookup means the card no longer exists and never will again.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        for entry in store.queued() {
            do {
                try await send(entry)
                store.remove(entry.id)
            } catch {
                if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                    store.remove(entry.id)
                    continue
                }
                return
            }
        }
    }
}
