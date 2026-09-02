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
    private let pendingAnswers: any PendingAnswerStore
    /// The last settings the server gave, kept because a session built with no
    /// connection has to use the same step lengths the server will recompute
    /// with — otherwise the offline due times and the flushed ones disagree.
    private let settingsCache: any DeckSnapshotStore
    private let flusher: PendingCardFlusher
    private let lookupFlusher: PendingLookupFlusher
    private let answerFlusher: PendingAnswerFlusher

    init(
        wrapping inner: any StudyRepository = APIStudyRepository(),
        pending: any PendingCardStore = InMemoryPendingCardStore(),
        pendingLookups: any PendingLookupStore = InMemoryPendingLookupStore(),
        pendingAnswers: any PendingAnswerStore = InMemoryPendingAnswerStore(),
        settingsCache: any DeckSnapshotStore = InMemoryDeckSnapshotStore()
    ) {
        self.inner = inner
        self.pending = pending
        self.pendingLookups = pendingLookups
        self.pendingAnswers = pendingAnswers
        self.settingsCache = settingsCache
        self.answerFlusher = PendingAnswerFlusher(store: pendingAnswers) { answer in
            _ = try await inner.recordReview(
                cardID: answer.cardID,
                questionType: answer.questionType,
                isCorrect: answer.isCorrect,
                clientToken: answer.clientToken,
                localDate: Self.day(from: answer.localDate) ?? answer.answeredAt,
                answeredAt: answer.answeredAt,
                context: answer.context,
                elapsedMs: nil
            )
        }
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
        // Answers before the fetch, so the response this returns — which
        // becomes the new snapshot — already reflects them. A snapshot taken
        // first would be overwritten by a schedule the server had not yet been
        // told about.
        await answerFlusher.flush()
        // Cards first: a lookup can only be reported against a card the server
        // already has, so draining the card queue first is what gives the
        // lookups something to land on.
        await lookupFlusher.flush()
        return try await inner.cards()
    }

    /// Records the answer, or keeps it until the backend can be reached.
    ///
    /// **Queued now, where stage 4 refused to queue at all.** The reason it
    /// refused has gone: the ladder's once-a-day rule made the order answers
    /// arrived in load-bearing, and a queue could not promise it. The scheduler
    /// that replaced it is a pure function of a card's state and the answers
    /// against it, so replaying them in the order they were *given* — which is
    /// what `answeredAt` records — lands on the same place either way.
    ///
    /// The returned outcome is computed locally, by the same transition table
    /// the backend runs (`Scheduler.swift`). It is what the session runs on
    /// until the queue drains; the server's answer replaces it then.
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
        do {
            let outcome = try await inner.recordReview(
                cardID: cardID,
                questionType: questionType,
                isCorrect: isCorrect,
                clientToken: clientToken,
                localDate: localDate,
                answeredAt: answeredAt,
                context: context,
                elapsedMs: elapsedMs
            )
            // A success proves the network is back — the cheapest flush trigger
            // there is, and the same trick `collect` uses.
            await answerFlusher.flush()
            return outcome
        } catch {
            // A refusal is not a connection problem. The card is gone, or this
            // exact answer was already taken; queueing it would only offer the
            // server the same thing until the 4xx rule dropped it anyway.
            if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                throw error
            }
            let day = Self.dayFormatter.string(from: localDate)
            let answer = PendingAnswer(
                cardID: cardID,
                questionType: questionType,
                isCorrect: isCorrect,
                clientToken: clientToken,
                localDate: day,
                answeredAt: answeredAt,
                context: context
            )
            pendingAnswers.enqueue(answer)
            return localOutcome(for: answer, on: day)
        }
    }

    /// What the answer did, worked out here because nobody could be asked.
    ///
    /// A card the snapshot has never heard of gets an outcome that changes
    /// nothing: it is not in the deck this session was built from, so there is
    /// no local state to move and inventing one would be worse than admitting
    /// it. The queued answer still goes to the server, which does know.
    private func localOutcome(for answer: PendingAnswer, on day: String) -> ReviewOutcome {
        let deck = knownCards()
        guard var card = deck.first(where: { $0.id == answer.cardID }) else {
            return ReviewOutcome(
                state: .new,
                learningStep: nil,
                ladderStage: 0,
                previousStage: nil,
                introducedOn: nil,
                dueAt: answer.answeredAt,
                intervalChanged: false
            )
        }
        // Training schedules nothing, here as on the server.
        guard answer.context == .review else {
            return ReviewOutcome(
                state: card.state,
                learningStep: card.learningStep,
                ladderStage: card.ladderStage,
                previousStage: card.previousStage,
                introducedOn: card.introducedOn,
                dueAt: card.dueAt,
                intervalChanged: false
            )
        }

        let before = card.state == .review ? card.ladderStage : nil
        card.apply(
            nextSchedule(
                card.scheduling,
                correct: answer.isCorrect,
                answeredAt: answer.answeredAt,
                learningSteps: cachedSettings().learningSteps
            ),
            introducedOn: day
        )
        let after = card.state == .review ? card.ladderStage : nil
        return ReviewOutcome(
            state: card.state,
            learningStep: card.learningStep,
            ladderStage: card.ladderStage,
            previousStage: card.previousStage,
            introducedOn: card.introducedOn,
            dueAt: card.dueAt,
            intervalChanged: before != after
        )
    }

    /// The reader's scheduling settings, falling back to the last ones seen.
    ///
    /// The defaults stand in only for a reader who has never been online, which
    /// is a reader with an empty deck.
    func settings() async throws -> StudySettings {
        do {
            let current = try await inner.settings()
            if let data = try? JSONEncoder().encode(current) { settingsCache.store(data) }
            return current
        } catch {
            if APIConfig.isOriginUnreachable(error) { return cachedSettings() }
            throw error
        }
    }

    /// Passed straight through, and **never queued**.
    ///
    /// An offline edit has no derivable merge rule, only an invented one — the
    /// same argument this decorator already makes about editing a card. These
    /// decide how every card is scheduled, so two copies that disagreed would
    /// produce two different due times for the same answer.
    @discardableResult
    func updateSettings(_ settings: StudySettings) async throws -> StudySettings {
        let saved = try await inner.updateSettings(settings)
        if let data = try? JSONEncoder().encode(saved) { settingsCache.store(data) }
        return saved
    }

    private func cachedSettings() -> StudySettings {
        guard
            let data = settingsCache.data(),
            let stored = try? JSONDecoder().decode(StudySettings.self, from: data)
        else { return .fallback }
        return stored
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func day(from iso: String) -> Date? {
        dayFormatter.date(from: iso)
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

    @discardableResult
    func reset(id: Int) async throws -> LearningCard {
        // Deliberately **not** queued when it fails, the same as `delete` and
        // `update` above. Those three change a card the reader is looking at,
        // and a queued one would report success against a deck that still shows
        // the old standing until some later flush -- so the honest answer to no
        // connection is that it did not happen.
        let card = try await inner.reset(id: id)
        await flusher.flush()
        await lookupFlusher.flush()
        return card
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

    /// The last good snapshot **with the queued answers replayed over it**.
    ///
    /// Which is what makes a session work with no connection: a card answered
    /// wrong five minutes ago is back in the learning steps here, so the queue
    /// offers it again, exactly as it would have if the server had been asked.
    func knownCards() -> [LearningCard] {
        replaying(
            pendingAnswers.queued(),
            over: inner.knownCards(),
            learningSteps: cachedSettings().learningSteps
        )
    }

    /// Answers the server has not taken yet. Exposed for the same reason
    /// `queuedLines()` is: a screen that says "everything is saved" should be
    /// able to be right about it.
    func queuedAnswers() -> [PendingAnswer] {
        pendingAnswers.queued()
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
