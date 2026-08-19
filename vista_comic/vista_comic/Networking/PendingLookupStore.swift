//
//  PendingLookupStore.swift
//  vista_comic
//
//  Re-lookups that could not be reported (`vocabulary-review` stage 1,
//  ticket 05).
//
//  **Why report this at all**: the reader selecting a line they already
//  collected is the cleanest forgetting signal this system will ever get —
//  they just proved they had not retained it. Nothing displays the number in
//  stage 1. It is collected now because it **cannot be collected
//  retroactively**: stage 2 shows it, stage 3 weights scheduling by it, stage 4
//  weights sentence generation by it, and starting later means those stages
//  begin with a column of zeros.
//
//  **Only the positive is ever recorded.** Not looking a word up again is no
//  evidence of knowing it — the reader may simply not have reached that page.
//
//  **Repeats are the data, so this queue does not deduplicate.** Unlike
//  `PendingCardStore`, where two taps mean one word, two lookups mean the
//  reader forgot the same word twice, and collapsing them would erase exactly
//  the signal this exists to capture.
//

import Foundation

/// One re-lookup waiting to be reported.
struct PendingLookup: Hashable, Sendable, Codable, Identifiable {
    /// Generated here rather than derived from the card, because a card can be
    /// looked up many times and each of those is its own event.
    let id: UUID
    let cardID: Int
    /// When the reader looked it up. Orders the flush, and decides what goes
    /// first when the queue is full.
    var occurredAt: Date

    init(cardID: Int, occurredAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.cardID = cardID
        self.occurredAt = occurredAt
    }
}

/// Holds the re-lookups the backend has not taken yet.
protocol PendingLookupStore: Sendable {
    /// The most entries that may be held at once.
    var limit: Int { get }

    /// Records one re-lookup. Never merged with an existing entry for the same
    /// card: two lookups are two facts.
    func enqueue(_ lookup: PendingLookup)

    /// Everything waiting, oldest first — the order it is sent in.
    func queued() -> [PendingLookup]

    /// Drops an entry. Called **only** once the server has taken it, or when
    /// the server has refused it in a way retrying cannot fix.
    func remove(_ id: UUID)
}

extension PendingLookupStore {
    var limit: Int { PendingLookupLimits.maxEntries }
}

enum PendingLookupLimits {
    /// Generous, because these are cheap rows and losing one loses a signal
    /// that cannot be recovered — but still bounded, because this is storage
    /// the reader never asked for and cannot see.
    static let maxEntries = 500
}

// MARK: - Live implementation

/// The queue the app runs on: one small file under Application Support.
///
/// Persisted for the same reason the card queue is: a reader who closes the app
/// on the plane has not thrown away the evidence of what they forgot.
final class FilePendingLookupStore: PendingLookupStore, @unchecked Sendable {
    let limit: Int

    private let file: URL
    private let lock = NSLock()
    private var entries: [PendingLookup]

    init(root: URL? = nil, limit: Int = PendingLookupLimits.maxEntries) throws {
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
            .appendingPathComponent("PendingLookups", isDirectory: true)
    }

    func enqueue(_ lookup: PendingLookup) {
        lock.withLock {
            entries.append(lookup)
            entries.sort { $0.occurredAt < $1.occurredAt }
            if entries.count > limit {
                // Oldest first, matching every other queue here. A lost signal
                // is a shame; an unbounded file is a defect.
                entries.removeFirst(entries.count - limit)
            }
            persist()
        }
    }

    func queued() -> [PendingLookup] {
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
        // Best-effort: a queue that cannot be saved costs a signal, never the
        // reading and never the translation the reader is waiting on.
        try? data.write(to: file, options: .atomic)
    }

    private static func load(from file: URL) -> [PendingLookup] {
        guard
            let data = try? Data(contentsOf: file),
            let rows = try? JSONDecoder().decode([PendingLookup].self, from: data)
        else { return [] }
        return rows.sorted { $0.occurredAt < $1.occurredAt }
    }
}

/// An in-memory queue for tests, previews, and the app's launch fallback.
final class InMemoryPendingLookupStore: PendingLookupStore, @unchecked Sendable {
    let limit: Int

    private let lock = NSLock()
    private var entries: [PendingLookup] = []

    init(limit: Int = PendingLookupLimits.maxEntries) {
        self.limit = limit
    }

    func enqueue(_ lookup: PendingLookup) {
        lock.withLock {
            entries.append(lookup)
            entries.sort { $0.occurredAt < $1.occurredAt }
            if entries.count > limit {
                entries.removeFirst(entries.count - limit)
            }
        }
    }

    func queued() -> [PendingLookup] {
        lock.withLock { entries }
    }

    func remove(_ id: UUID) {
        lock.withLock { entries.removeAll { $0.id == id } }
    }
}
