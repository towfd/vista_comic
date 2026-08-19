//
//  PendingCardStore.swift
//  vista_comic
//
//  Words collected while the backend could not be reached
//  (`vocabulary-review` stage 1, ticket 04).
//
//  **Why this exists at all**: offline download shipped, so reading offline is
//  now ordinary — and reading offline is exactly when the most words get looked
//  up. A collection step that needed a connection would miss the reader's
//  densest collecting sessions, and the deck is the one thing in this feature
//  that cannot be caught up later by working harder. Every other stage is
//  downstream of how many cards exist.
//
//  **This is a catch-up queue, not a sync engine**, on the same terms as
//  `PendingProgressStore`: the backend stays the source of truth, there is no
//  merge policy and no conflict resolution. A line waits here only until the
//  server takes it, and is then gone.
//
//  **Kept apart from `DeckSnapshotStore` on purpose.** The two have opposite
//  lifetimes: a snapshot is replaced wholesale whenever a fresher one arrives,
//  a queued line disappears only once the server has accepted it, and neither
//  event has any business disturbing the other.
//

import Foundation

/// One line collected offline, waiting to be sent.
struct PendingCard: Hashable, Sendable, Codable {
    let sourceText: String
    let translation: String
    let targetLanguage: String
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// When this line was queued. Orders the flush, and decides what goes first
    /// when the queue is full.
    var queuedAt: Date

    init(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        queuedAt: Date = Date()
    ) {
        self.sourceText = sourceText
        self.translation = translation
        self.targetLanguage = targetLanguage
        self.comicID = comicID
        self.chapterID = chapterID
        self.pageNumber = pageNumber
        self.queuedAt = queuedAt
    }

    /// The card identity this line will have once the server has it — the same
    /// normalised key plus target language the backend enforces.
    ///
    /// Computed rather than stored so it can never be persisted under one
    /// version of the rule and compared under another.
    var identity: CardIdentity {
        CardIdentity(key: normalizedKey(sourceText), targetLanguage: targetLanguage)
    }
}

/// What makes two collected lines the same card, on this side of the wire.
struct CardIdentity: Hashable, Sendable {
    let key: String
    let targetLanguage: String
}

/// Holds the lines the backend has not taken yet.
///
/// **One entry per card identity, first write wins.** Tapping add twice on the
/// same line while offline queues one entry, not two — the backend would
/// collapse them anyway (its `POST /cards` is idempotent), but doing it here
/// means the queue length reflects words rather than taps.
protocol PendingCardStore: Sendable {
    /// The most entries that may be held at once.
    var limit: Int { get }

    /// Records `card` unless an equivalent line is already waiting.
    ///
    /// At the limit the oldest entry is dropped. Bounded deliberately: this is
    /// storage the reader never asked for and cannot see, so it must not be
    /// able to grow without one.
    func enqueue(_ card: PendingCard)

    /// Everything waiting, oldest first — the order it is sent in.
    func queued() -> [PendingCard]

    /// Drops an entry. Called **only** once the server has accepted it, or when
    /// the server has refused it in a way retrying cannot fix.
    func remove(_ identity: CardIdentity)
}

extension PendingCardStore {
    var limit: Int { PendingCardLimits.maxEntries }
}

enum PendingCardLimits {
    /// Words collected while unreachable. Far past a flight's worth of
    /// deliberate, hand-picked additions; small enough that flushing it is
    /// never a long wait.
    static let maxEntries = 200
}

// MARK: - Live implementation

/// The queue the app runs on: one small file under Application Support.
///
/// **It persists, and that is the point.** A reader who closes the app on the
/// plane has not thrown away the words they picked out — the queue is still
/// there when they land, which is when it can finally be sent.
final class FilePendingCardStore: PendingCardStore, @unchecked Sendable {
    let limit: Int

    private let file: URL
    private let lock = NSLock()
    private var entries: [CardIdentity: PendingCard]

    init(root: URL? = nil, limit: Int = PendingCardLimits.maxEntries) throws {
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
            .appendingPathComponent("PendingCards", isDirectory: true)
    }

    func enqueue(_ card: PendingCard) {
        lock.withLock {
            // First write wins, unlike `PendingProgressStore`'s last-write-wins:
            // a position gets better as the reader advances, but a collected
            // line does not change, and the earlier `queuedAt` is the one that
            // reflects when they actually chose it.
            guard entries[card.identity] == nil else { return }
            entries[card.identity] = card
            if entries.count > limit,
               let oldest = entries.values.min(by: { $0.queuedAt < $1.queuedAt }) {
                entries[oldest.identity] = nil
            }
            persist()
        }
    }

    func queued() -> [PendingCard] {
        lock.withLock { Array(entries.values) }
            .sorted { $0.queuedAt < $1.queuedAt }
    }

    func remove(_ identity: CardIdentity) {
        lock.withLock {
            entries[identity] = nil
            persist()
        }
    }

    /// Rewrites the whole queue. One small file of at most `limit` rows, written
    /// only when the reader deliberately adds a word, so there is nothing here
    /// worth an incremental format.
    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        // Best-effort, like every other write in this area: a queue that cannot
        // be saved costs the words picked in this session, never the reading.
        try? data.write(to: file, options: .atomic)
    }

    private static func load(from file: URL) -> [CardIdentity: PendingCard] {
        guard
            let data = try? Data(contentsOf: file),
            let rows = try? JSONDecoder().decode([PendingCard].self, from: data)
        else { return [:] }
        return Dictionary(rows.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// An in-memory queue for tests, previews, and the app's launch fallback.
/// With nowhere to persist it, collecting offline still works for as long as
/// the app is running — which is no worse than not having the queue.
final class InMemoryPendingCardStore: PendingCardStore, @unchecked Sendable {
    let limit: Int

    private let lock = NSLock()
    private var entries: [CardIdentity: PendingCard] = [:]

    init(limit: Int = PendingCardLimits.maxEntries) {
        self.limit = limit
    }

    func enqueue(_ card: PendingCard) {
        lock.withLock {
            guard entries[card.identity] == nil else { return }
            entries[card.identity] = card
            if entries.count > limit,
               let oldest = entries.values.min(by: { $0.queuedAt < $1.queuedAt }) {
                entries[oldest.identity] = nil
            }
        }
    }

    func queued() -> [PendingCard] {
        lock.withLock { Array(entries.values) }
            .sorted { $0.queuedAt < $1.queuedAt }
    }

    func remove(_ identity: CardIdentity) {
        lock.withLock { entries[identity] = nil }
    }
}
