//
//  PendingAnswerStore.swift
//  vista_comic
//
//  Answers that could not be sent (`vocabulary-review` stage 6, ticket 07).
//
//  The fourth queue of this shape, after cards, lookups and progress, and the
//  first whose entries the app also *reads back*: the deck the session is built
//  from is the last good snapshot with these replayed over it, which is how a
//  card answered in airplane mode comes back five minutes later without a
//  server ever hearing about it.
//
//  **Written the moment the answer is given, never at the end of a session.**
//  An answer is an event that cannot be reconstructed. Saving on exit would
//  lose a whole sitting to a crash, and would make leaving the app feel
//  expensive — the opposite of what "stop any time" is for.
//
//  **Nothing here deduplicates.** Two answers to the same card are two facts,
//  and the second is usually the interesting one: the card came back because
//  the first was wrong.
//

import Foundation

/// One answer waiting to be reported.
///
/// Carries its own `clientToken`, generated when the question was built, so a
/// flush that half-succeeds cannot count an answer twice — the backend's
/// uniqueness constraint recognises it as the same answer.
struct PendingAnswer: Hashable, Sendable, Codable, Identifiable {
    let id: UUID
    let cardID: Int
    let questionType: ReviewQuestionType
    let isCorrect: Bool
    let clientToken: String
    /// The reader's day, as the backend groups by. A string because a
    /// scheduling day is not an instant.
    let localDate: String
    /// When the reader actually answered — the whole reason this queue can
    /// exist without the schedule going wrong.
    let answeredAt: Date
    let context: ReviewContext

    init(
        cardID: Int,
        questionType: ReviewQuestionType,
        isCorrect: Bool,
        clientToken: String,
        localDate: String,
        answeredAt: Date,
        context: ReviewContext,
        id: UUID = UUID()
    ) {
        self.id = id
        self.cardID = cardID
        self.questionType = questionType
        self.isCorrect = isCorrect
        self.clientToken = clientToken
        self.localDate = localDate
        self.answeredAt = answeredAt
        self.context = context
    }
}

/// Holds the answers the backend has not taken yet.
protocol PendingAnswerStore: Sendable {
    var limit: Int { get }

    /// Records one answer. Never merged with an existing entry.
    func enqueue(_ answer: PendingAnswer)

    /// Everything waiting, **oldest first** — which is both the order it is
    /// sent in and the order it must be replayed in, since each answer's effect
    /// depends on where the previous one left the card.
    func queued() -> [PendingAnswer]

    /// Drops an entry, once the server has taken it or refused it in a way
    /// retrying cannot fix.
    func remove(_ id: UUID)
}

extension PendingAnswerStore {
    var limit: Int { PendingAnswerLimits.maxEntries }
}

enum PendingAnswerLimits {
    /// A long flight is a few hundred answers at most. Bounded anyway, because
    /// this is storage the reader never asked for and cannot see.
    static let maxEntries = 1000
}

// MARK: - Live implementation

/// The queue the app runs on: one small file under Application Support.
final class FilePendingAnswerStore: PendingAnswerStore, @unchecked Sendable {
    let limit: Int
    private let file: URL
    private let lock = NSLock()
    private var entries: [PendingAnswer]

    init(root: URL? = nil, limit: Int = PendingAnswerLimits.maxEntries) throws {
        var resolvedRoot = try root ?? Self.defaultRoot()
        try FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resolvedRoot.setResourceValues(values)

        self.limit = limit
        self.file = resolvedRoot.appendingPathComponent("queue.json")
        self.entries = Self.load(from: self.file)
    }

    static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PendingAnswers", isDirectory: true)
    }

    func enqueue(_ answer: PendingAnswer) {
        lock.withLock {
            entries.append(answer)
            entries.sort { $0.answeredAt < $1.answeredAt }
            if entries.count > limit {
                entries.removeFirst(entries.count - limit)
            }
            persist()
        }
    }

    func queued() -> [PendingAnswer] {
        lock.withLock { entries }
    }

    func remove(_ id: UUID) {
        lock.withLock {
            entries.removeAll { $0.id == id }
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func load(from file: URL) -> [PendingAnswer] {
        guard
            let data = try? Data(contentsOf: file),
            let rows = try? JSONDecoder().decode([PendingAnswer].self, from: data)
        else { return [] }
        return rows.sorted { $0.answeredAt < $1.answeredAt }
    }
}

/// For tests and for a device with nowhere to write: the queue still works
/// within a launch, and a relaunch loses it — no worse than not having it.
final class InMemoryPendingAnswerStore: PendingAnswerStore, @unchecked Sendable {
    let limit: Int
    private let lock = NSLock()
    private var entries: [PendingAnswer] = []

    init(limit: Int = PendingAnswerLimits.maxEntries) {
        self.limit = limit
    }

    func enqueue(_ answer: PendingAnswer) {
        lock.withLock {
            entries.append(answer)
            entries.sort { $0.answeredAt < $1.answeredAt }
            if entries.count > limit {
                entries.removeFirst(entries.count - limit)
            }
        }
    }

    func queued() -> [PendingAnswer] { lock.withLock { entries } }

    func remove(_ id: UUID) {
        lock.withLock { entries.removeAll { $0.id == id } }
    }
}

// MARK: - Replay

/// The deck as the queued answers have left it.
///
/// **The property the whole design rests on**: scheduling is a pure function of
/// a card's state and the answers against it, so replaying the queue over the
/// last good snapshot lands on the same place the backend will land on when the
/// queue reaches it. Nothing has to be reconciled — the server recomputes from
/// the same answers and its result simply replaces this.
///
/// `training` answers are skipped, exactly as the backend skips them.
func replaying(
    _ answers: [PendingAnswer],
    over deck: [LearningCard],
    learningSteps: [Int]
) -> [LearningCard] {
    var byID = Dictionary(uniqueKeysWithValues: deck.map { ($0.id, $0) })
    for answer in answers.sorted(by: { $0.answeredAt < $1.answeredAt }) {
        guard answer.context == .review, var card = byID[answer.cardID] else { continue }
        card.apply(
            nextSchedule(
                card.scheduling,
                correct: answer.isCorrect,
                answeredAt: answer.answeredAt,
                learningSteps: learningSteps
            ),
            introducedOn: answer.localDate
        )
        byID[answer.cardID] = card
    }
    // Back in the deck's own order: the queue must not reshuffle the library.
    return deck.compactMap { byID[$0.id] }
}

/// Drains `PendingAnswerStore`, oldest first, never twice at once.
///
/// Each answer carries the timestamp it was given at, so arriving late costs
/// nothing — the backend schedules from `answeredAt`, not from now.
actor PendingAnswerFlusher {
    private let store: any PendingAnswerStore
    private let send: @Sendable (PendingAnswer) async throws -> Void
    private var isFlushing = false

    init(
        store: any PendingAnswerStore,
        send: @escaping @Sendable (PendingAnswer) async throws -> Void
    ) {
        self.store = store
        self.send = send
    }

    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        for entry in store.queued() {
            do {
                try await send(entry)
                store.remove(entry.id)
            } catch {
                // A 4xx means the card is gone, or the answer was already
                // taken. Neither improves by being sent again, and an entry
                // that can never leave would block everything behind it.
                if case APIError.httpStatus(let code) = error, (400..<500).contains(code) {
                    store.remove(entry.id)
                    continue
                }
                return
            }
        }
    }
}
