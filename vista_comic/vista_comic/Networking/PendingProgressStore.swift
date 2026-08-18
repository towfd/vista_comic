//
//  PendingProgressStore.swift
//  vista_comic
//
//  Reading positions that could not be sent (`offline-download` ticket 03).
//
//  Progress writes have always been swallowed on failure, and that was right
//  when a failure meant a passing blip: a progress store that is down must
//  never interrupt reading. Once reading offline is a normal thing to do, the
//  same rule quietly discards an entire session — and what the reader sees is
//  an app that forgot several hours of reading.
//
//  **This is a catch-up queue, not a sync engine.** The backend stays the
//  source of truth for progress. There is no merge policy, no conflict
//  resolution and no local-first store; a position waits here only until the
//  server takes it, and is then gone.
//
//  **Kept apart from `OfflineChapterStore` on purpose.** The two have genuinely
//  different lifetimes: downloaded content disappears when the cap evicts it,
//  a queued position disappears only once the server has accepted it, and
//  neither event has any business disturbing the other. Evicting the chapter
//  someone read on a plane must not throw away where they got to in it.
//

import Foundation

/// One chapter's furthest-read page, waiting to be sent.
struct PendingProgress: Hashable, Sendable, Codable {
    let comicID: String
    let chapterID: String
    /// 1-based, matching the backend's contract.
    var lastPage: Int
    /// When this position was queued. Orders the flush, and decides what goes
    /// first when the queue is full.
    var queuedAt: Date

    var id: DownloadedChapterID {
        DownloadedChapterID(comicID: comicID, chapterID: chapterID)
    }

    init(comicID: String, chapterID: String, lastPage: Int, queuedAt: Date = Date()) {
        self.comicID = comicID
        self.chapterID = chapterID
        self.lastPage = lastPage
        self.queuedAt = queuedAt
    }
}

/// Holds the positions the backend has not taken yet.
///
/// **One entry per chapter, last write wins.** A whole offline session collapses
/// to one row per chapter rather than a log of every page turn, which is what
/// keeps this a queue of tens of entries instead of thousands — and it loses
/// nothing, because the only position worth sending is the furthest one.
protocol PendingProgressStore: Sendable {
    /// The most entries that may be held at once.
    var limit: Int { get }

    /// Records `progress`, replacing any earlier entry for the same chapter.
    ///
    /// At the limit, the oldest entry is dropped. Bounded deliberately: this is
    /// storage the reader never asked for and cannot see, so it must not be
    /// able to grow without one.
    func enqueue(_ progress: PendingProgress)

    /// Everything waiting, oldest first — the order it is sent in.
    func queued() -> [PendingProgress]

    /// What is queued for one chapter, if anything. Lets a chapter opened
    /// offline resume where the reader actually got to rather than at the top.
    func progress(for chapterID: DownloadedChapterID) -> PendingProgress?

    /// Drops an entry. Called **only** once the server has accepted it.
    func remove(_ chapterID: DownloadedChapterID)
}

extension PendingProgressStore {
    var limit: Int { PendingProgressLimits.maxEntries }
}

enum PendingProgressLimits {
    /// One per chapter, so this is "chapters read while unreachable". Well past
    /// a flight; small enough that flushing it can never be a long wait.
    static let maxEntries = 100
}

// MARK: - Live implementation

/// The queue the app runs on: one small file under Application Support.
///
/// **It persists, and that is the point.** A reader who closes the app on the
/// plane has not thrown their session away — the queue is still there when they
/// land, which is exactly when it can finally be sent.
final class FilePendingProgressStore: PendingProgressStore, @unchecked Sendable {
    let limit: Int

    private let file: URL
    private let lock = NSLock()
    private var entries: [DownloadedChapterID: PendingProgress]

    init(root: URL? = nil, limit: Int = PendingProgressLimits.maxEntries) throws {
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
            .appendingPathComponent("PendingProgress", isDirectory: true)
    }

    func enqueue(_ progress: PendingProgress) {
        lock.withLock {
            entries[progress.id] = progress
            if entries.count > limit,
               let oldest = entries.values.min(by: { $0.queuedAt < $1.queuedAt }) {
                entries[oldest.id] = nil
            }
            persist()
        }
    }

    func queued() -> [PendingProgress] {
        lock.withLock { Array(entries.values) }
            .sorted { $0.queuedAt < $1.queuedAt }
    }

    func progress(for chapterID: DownloadedChapterID) -> PendingProgress? {
        lock.withLock { entries[chapterID] }
    }

    func remove(_ chapterID: DownloadedChapterID) {
        lock.withLock {
            entries[chapterID] = nil
            persist()
        }
    }

    /// Rewrites the whole queue. It is one small file of at most `limit` rows,
    /// and a write per page turn is already debounced by the Reader, so there
    /// is nothing here worth an incremental format.
    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        // Best-effort, like every other write in this feature: a queue that
        // cannot be saved costs a session's progress, never the reading itself.
        try? data.write(to: file, options: .atomic)
    }

    private static func load(from file: URL) -> [DownloadedChapterID: PendingProgress] {
        guard
            let data = try? Data(contentsOf: file),
            let rows = try? JSONDecoder().decode([PendingProgress].self, from: data)
        else { return [:] }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// An in-memory queue for previews and for the app's launch fallback.
final class InMemoryPendingProgressStore: PendingProgressStore, @unchecked Sendable {
    let limit: Int

    private let lock = NSLock()
    private var entries: [DownloadedChapterID: PendingProgress] = [:]

    init(limit: Int = PendingProgressLimits.maxEntries) {
        self.limit = limit
    }

    func enqueue(_ progress: PendingProgress) {
        lock.withLock {
            entries[progress.id] = progress
            if entries.count > limit,
               let oldest = entries.values.min(by: { $0.queuedAt < $1.queuedAt }) {
                entries[oldest.id] = nil
            }
        }
    }

    func queued() -> [PendingProgress] {
        lock.withLock { Array(entries.values) }
            .sorted { $0.queuedAt < $1.queuedAt }
    }

    func progress(for chapterID: DownloadedChapterID) -> PendingProgress? {
        lock.withLock { entries[chapterID] }
    }

    func remove(_ chapterID: DownloadedChapterID) {
        lock.withLock { entries[chapterID] = nil }
    }
}
