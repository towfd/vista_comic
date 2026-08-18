//
//  OfflineChapterStore.swift
//  vista_comic
//
//  The content seam of `offline-download` (ticket 01): what is on the device,
//  and everything needed to assemble it back into a readable chapter later.
//  Injected through the environment like `ComicRepository` and `PageImageCache`,
//  so tests point it at a temporary directory and previews substitute a double.
//
//  **The chapter record is load-bearing, not bookkeeping.** A chapter's ordered
//  page URLs are only ever known from a live `GET /comics/{id}/chapters/{cid}`;
//  the chapter *summary* the list screen holds carries no pages at all. Without
//  a stored record, the bytes on disk cannot be reassembled into a chapter no
//  matter how many of them there are, so the record is written before the first
//  page is fetched rather than after the last.
//
//  Ticket 01 delivered the bytes and the record. Ticket 02 adds the one way to
//  read them back — `pageData(for:)`, keyed by URL alone, which the image cache
//  consults before the network. There is deliberately no write counterpart to
//  it: only the download engine puts anything here.
//

import CryptoKit
import Foundation
import SwiftUI

// MARK: - What a download is

/// Identifies one downloaded chapter. Also the key the download engine tracks
/// in-flight work under, so "which chapter is this?" has one spelling.
struct DownloadedChapterID: Hashable, Sendable, Codable {
    let comicID: String
    let chapterID: String

    init(comicID: String, chapterID: String) {
        self.comicID = comicID
        self.chapterID = chapterID
    }
}

/// One chapter kept on the device, and everything needed to display and read it
/// with no connection.
///
/// The comic's title travels with it because the 已下載 screen (ticket 05) has to
/// group by comic while the library catalog may be unreachable — a downloaded
/// chapter that can only say which comic id it belongs to is not something a
/// reader can be shown.
struct DownloadedChapter: Identifiable, Hashable, Sendable, Codable {
    let comicID: String
    let comicTitle: String
    let chapterID: String
    let chapterNumber: Int
    let chapterTitle: String
    /// The ordered page URLs, learned from the reader endpoint. Empty between
    /// admitting the chapter and resolving it — see the file comment.
    var pageURLs: [URL]
    /// What the chapter list said the page count was, until `pageURLs` replaces
    /// it with the real thing. Drives the progress ring before the first fetch.
    var pageCount: Int
    /// When the download was started. The FIFO key ticket 04 evicts by, so it is
    /// recorded from the first moment a slot is occupied and never updated.
    let startedAt: Date
    /// `true` only once every page is present on disk. A chapter that is
    /// partially downloaded is not readable offline and must never claim to be.
    var isComplete: Bool

    var id: DownloadedChapterID {
        DownloadedChapterID(comicID: comicID, chapterID: chapterID)
    }

    init(
        comicID: String,
        comicTitle: String,
        chapterID: String,
        chapterNumber: Int,
        chapterTitle: String,
        pageURLs: [URL] = [],
        pageCount: Int = 0,
        startedAt: Date = Date(),
        isComplete: Bool = false
    ) {
        self.comicID = comicID
        self.comicTitle = comicTitle
        self.chapterID = chapterID
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.pageURLs = pageURLs
        self.pageCount = pageCount
        self.startedAt = startedAt
        self.isComplete = isComplete
    }
}

/// How much the device is allowed to hold. One constant, no settings screen.
enum OfflineDownloadLimits {
    /// Chapters, counted across the whole library — 5–20 MB each, so roughly
    /// 100–400 MB in total.
    static let maxChapters = 20
}

enum OfflineDownloadError: Error, Equatable {
    /// The device is full and there is nothing that may be evicted — which, at
    /// a cap of twenty and exactly one chapter ever protected, means the cap is
    /// one. Kept as an error rather than treated as impossible so that a store
    /// configured small in a test says something honest.
    case chapterLimitReached
    /// Asked to update a chapter that was never admitted. A record is what
    /// reserves the slot, so writing one that never claimed a slot would let the
    /// cap be walked straight past.
    case unknownChapter
    /// Some pages never arrived. The chapter keeps what it has for the next
    /// attempt to resume from, but it is not complete and cannot be read offline.
    case incompleteChapter
}

// MARK: - The seam

/// Owns downloaded *content*: chapter records, page bytes, and deletion.
///
/// Synchronous by design, like `PageImageCache`'s `cachedImage(for:)` and for
/// the same reason: a chapter row asks "is this downloaded?" while its `body` is
/// being evaluated, where `await` is not available. Records are held in memory,
/// so answering costs a dictionary lookup rather than a disk read.
protocol OfflineChapterStore: Sendable {
    /// How many chapters may be held at once.
    var chapterLimit: Int { get }

    /// Every chapter on the device, oldest download first — the order ticket 04
    /// will evict in.
    func downloadedChapters() -> [DownloadedChapter]

    func downloadedChapter(_ id: DownloadedChapterID) -> DownloadedChapter?

    /// Reserves a slot and writes the chapter's record, evicting the oldest
    /// download if the device is already full.
    ///
    /// **A download occupies its slot from the moment it starts**, not when it
    /// finishes: otherwise queueing several at once would sail past the cap
    /// while every one of them was still in flight.
    ///
    /// **Eviction is per chapter admitted**, so admitting five at the cap evicts
    /// exactly five — the semantics ticket 06's batch download relies on,
    /// settled here with the logic rather than discovered there.
    ///
    /// **Strict first-in-first-out by `startedAt`.** Read state is deliberately
    /// not consulted: a rule the reader can predict without knowing what the app
    /// thinks they have read is worth more than a cleverer one.
    ///
    /// Admitting a chapter that is already admitted is a no-op rather than an
    /// error, so resuming an interrupted download does not consume a second
    /// slot — and does not reset `startedAt`, which is the eviction key.
    ///
    /// - Parameter protecting: a chapter that must not be evicted whatever its
    ///   age — the one open in the Reader. Deleting the pages out from under
    ///   someone who is reading them is never the right answer.
    /// - Returns: the chapter evicted to make room, or `nil` if there was room.
    /// - Throws: `OfflineDownloadError.chapterLimitReached` when the device is
    ///   full and every chapter on it is protected.
    @discardableResult
    func admit(
        _ chapter: DownloadedChapter,
        protecting: DownloadedChapterID?
    ) throws -> DownloadedChapterID?

    /// Rewrites an admitted chapter's record — the page URLs once the reader
    /// endpoint has answered, and the completion flag once every page is present.
    ///
    /// - Throws: `OfflineDownloadError.unknownChapter` if it was never admitted.
    func update(_ chapter: DownloadedChapter) throws

    /// Whether this page is already on disk. This is what makes resume
    /// page-level: an interrupted chapter costs only what had not yet arrived,
    /// which matters when a chapter is 60–180 separate requests.
    func hasPage(_ url: URL, of chapterID: DownloadedChapterID) -> Bool

    func writePage(_ data: Data, for url: URL, of chapterID: DownloadedChapterID) throws

    /// The bytes of a downloaded page, from whichever chapter downloaded it, or
    /// `nil` if this URL is not on the device (ticket 02).
    ///
    /// Keyed by URL alone, with no chapter to say where to look, because that is
    /// all the image cache knows: it resolves a URL, and has no idea which
    /// chapter — or whether a chapter at all — the picture belongs to.
    ///
    /// **Reading never writes.** There is deliberately no counterpart that puts
    /// a page here on its way past; only the download engine writes. The moment
    /// a page merely read gets kept, three things that must agree stop agreeing:
    /// what the 已下載 list shows, what counts against the cap, and what is
    /// actually on the device.
    func pageData(for url: URL) -> Data?

    /// Removes the chapter's record and its page files together, freeing its slot.
    func delete(_ chapterID: DownloadedChapterID) throws

    /// How many bytes this chapter occupies on the device (ticket 05).
    ///
    /// Measured rather than remembered: a record written before the first page
    /// arrived cannot know, and a partly downloaded chapter's size changes as it
    /// fills. Walks the chapter's files, so call it off the main thread — the
    /// 已下載 screen does exactly that while it loads.
    func sizeOnDisk(of chapterID: DownloadedChapterID) -> Int64
}

extension OfflineChapterStore {
    var chapterLimit: Int { OfflineDownloadLimits.maxChapters }

    /// Admits with nothing protected — for every caller that is not the download
    /// engine, since the engine is the only one that knows what is being read.
    @discardableResult
    func admit(_ chapter: DownloadedChapter) throws -> DownloadedChapterID? {
        try admit(chapter, protecting: nil)
    }

    /// Whether every page of this chapter is present — the only definition of
    /// "readable offline" anything should use.
    func isComplete(_ chapterID: DownloadedChapterID) -> Bool {
        downloadedChapter(chapterID)?.isComplete ?? false
    }
}

// MARK: - Live implementation

/// The store the app runs on: one directory per chapter under Application
/// Support.
///
/// **Application Support, not Caches.** The system reclaims Caches under disk
/// pressure, which would silently delete the one thing this feature exists to
/// guarantee — and it would do it exactly when the reader is furthest from a
/// connection. The directory is marked excluded from iCloud backup, so a few
/// hundred megabytes of comics never inflate the reader's backup.
///
/// Thread safety follows `DecodedImageStore`'s shape rather than an actor's: the
/// record index is guarded by a lock so any thread may read it synchronously,
/// which is what lets a row consult it mid-layout. Page files need no lock at
/// all — their paths are derived from the URL, so four concurrent writes touch
/// four different files.
final class FileOfflineChapterStore: OfflineChapterStore, @unchecked Sendable {
    let chapterLimit: Int

    private let root: URL
    private let fileManager = FileManager.default
    /// Guards `records` only. Everything else here is derived from its arguments.
    private let lock = NSLock()
    private var records: [DownloadedChapterID: DownloadedChapter]
    /// Which chapter downloaded a given page, so a URL on its own is enough to
    /// find its bytes — the only thing the image cache can ask with.
    /// Derived from the records; nothing is authoritative here.
    private var pageOwners: [URL: DownloadedChapterID]

    /// - Parameter root: where downloads live. Tests pass a temporary directory;
    ///   nothing may ever write to the real Application Support path from a test.
    init(root: URL? = nil, chapterLimit: Int = OfflineDownloadLimits.maxChapters) throws {
        let resolvedRoot = try root ?? Self.defaultRoot()
        self.root = resolvedRoot
        self.chapterLimit = chapterLimit
        try Self.prepare(directory: resolvedRoot)
        let records = Self.loadRecords(in: resolvedRoot)
        self.records = records
        self.pageOwners = Self.pageOwners(of: records.values)
    }

    /// `Application Support/OfflineChapters`, created if it does not exist —
    /// unlike Caches, Application Support is not guaranteed to be there.
    static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("OfflineChapters", isDirectory: true)
    }

    // MARK: Records

    func downloadedChapters() -> [DownloadedChapter] {
        lock.withLock { Array(records.values) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func downloadedChapter(_ id: DownloadedChapterID) -> DownloadedChapter? {
        lock.withLock { records[id] }
    }

    @discardableResult
    func admit(
        _ chapter: DownloadedChapter,
        protecting: DownloadedChapterID?
    ) throws -> DownloadedChapterID? {
        try lock.withLock {
            // Already holds a slot: this is a resume, not a new download.
            guard records[chapter.id] == nil else { return nil }

            var evicted: DownloadedChapterID?
            if records.count >= chapterLimit {
                guard let victim = oldestEvictable(protecting: protecting) else {
                    throw OfflineDownloadError.chapterLimitReached
                }
                try remove(victim)
                evicted = victim
            }

            try writeRecord(chapter)
            records[chapter.id] = chapter
            index(chapter)
            return evicted
        }
    }

    func update(_ chapter: DownloadedChapter) throws {
        try lock.withLock {
            guard records[chapter.id] != nil else {
                throw OfflineDownloadError.unknownChapter
            }
            try writeRecord(chapter)
            records[chapter.id] = chapter
            index(chapter)
        }
    }

    func delete(_ chapterID: DownloadedChapterID) throws {
        try lock.withLock { try remove(chapterID) }
    }

    func sizeOnDisk(of chapterID: DownloadedChapterID) -> Int64 {
        // The pages, not the whole chapter directory: what the reader is being
        // shown is what the content costs, and the record beside it is a few
        // hundred bytes of bookkeeping they did not ask about. It also makes a
        // just-admitted chapter honestly report nothing yet.
        let directory = pagesDirectory(for: chapterID)
        guard
            let files = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }

        var total: Int64 = 0
        for case let file as URL in files {
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += Int64(size ?? 0)
        }
        return total
    }

    /// The chapter that has been on the device longest and may go.
    ///
    /// Strict first-in-first-out, and nothing else is consulted — not read
    /// state, not size, not how recently it was opened.
    private func oldestEvictable(protecting: DownloadedChapterID?) -> DownloadedChapterID? {
        records.values
            .filter { $0.id != protecting }
            .min { $0.startedAt < $1.startedAt }?
            .id
    }

    /// Removes a chapter's record and its files together. The caller holds the
    /// lock; eviction and explicit deletion are the same act and must not drift.
    private func remove(_ chapterID: DownloadedChapterID) throws {
        records[chapterID] = nil
        pageOwners = pageOwners.filter { $0.value != chapterID }
        let directory = directory(for: chapterID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    // MARK: Pages

    func hasPage(_ url: URL, of chapterID: DownloadedChapterID) -> Bool {
        fileManager.fileExists(atPath: pageFile(for: url, of: chapterID).path)
    }

    func writePage(_ data: Data, for url: URL, of chapterID: DownloadedChapterID) throws {
        let file = pageFile(for: url, of: chapterID)
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic so a download killed mid-write leaves the page absent rather
        // than half-present — resume trusts "the file is there" completely.
        try data.write(to: file, options: .atomic)
    }

    func pageData(for url: URL) -> Data? {
        guard let owner = lock.withLock({ pageOwners[url] }) else { return nil }
        // Read outside the lock: the index answers where to look, and the bytes
        // are a page-sized disk read that no record lookup should wait behind.
        return try? Data(contentsOf: pageFile(for: url, of: owner))
    }

    private func index(_ chapter: DownloadedChapter) {
        for url in chapter.pageURLs {
            pageOwners[url] = chapter.id
        }
    }

    private static func pageOwners(
        of chapters: some Collection<DownloadedChapter>
    ) -> [URL: DownloadedChapterID] {
        var owners: [URL: DownloadedChapterID] = [:]
        for chapter in chapters {
            for url in chapter.pageURLs {
                owners[url] = chapter.id
            }
        }
        return owners
    }

    // MARK: Layout on disk

    /// One directory per chapter, named from a digest of its ids rather than
    /// from the ids themselves: they are server-generated strings, and a path
    /// separator arriving inside one would otherwise write outside the root.
    /// The real ids are inside the record, which is what the index is rebuilt
    /// from, so the opaque name costs nothing.
    private func directory(for chapterID: DownloadedChapterID) -> URL {
        root.appendingPathComponent(
            Self.digest("\(chapterID.comicID)\u{0}\(chapterID.chapterID)"),
            isDirectory: true
        )
    }

    private func recordFile(for chapterID: DownloadedChapterID) -> URL {
        directory(for: chapterID).appendingPathComponent("record.json")
    }

    /// Page files are named from the page URL, so the disk store is keyed the
    /// same way the memory cache is — which is what lets ticket 02 put the disk
    /// in front of the network with a single lookup.
    private func pageFile(for url: URL, of chapterID: DownloadedChapterID) -> URL {
        pagesDirectory(for: chapterID)
            .appendingPathComponent(Self.digest(url.absoluteString))
    }

    private func pagesDirectory(for chapterID: DownloadedChapterID) -> URL {
        directory(for: chapterID).appendingPathComponent("pages", isDirectory: true)
    }

    private func writeRecord(_ chapter: DownloadedChapter) throws {
        let file = recordFile(for: chapter.id)
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(chapter).write(to: file, options: .atomic)
    }

    private static func prepare(directory: URL) throws {
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    /// Rebuilds the index by reading each chapter directory's record.
    ///
    /// A record that cannot be decoded is skipped rather than fatal: one
    /// unreadable file must cost one chapter, not the whole feature. It keeps
    /// its directory, so its slot is not silently reused by a partial download
    /// nobody can see.
    private static func loadRecords(in root: URL) -> [DownloadedChapterID: DownloadedChapter] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []

        var records: [DownloadedChapterID: DownloadedChapter] = [:]
        for directory in directories {
            let file = directory.appendingPathComponent("record.json")
            guard
                let data = try? Data(contentsOf: file),
                let record = try? decoder.decode(DownloadedChapter.self, from: data)
            else { continue }
            records[record.id] = record
        }
        return records
    }

    /// Stock date handling — a `Double` — rather than ISO-8601 strings, which
    /// are more legible on disk but are written to whole seconds. `startedAt` is
    /// the key downloads are evicted by, and two chapters queued in the same
    /// second would then have no order at all.
    private static var encoder: JSONEncoder { JSONEncoder() }

    private static var decoder: JSONDecoder { JSONDecoder() }

    private static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Preview / fallback implementation

/// An `OfflineChapterStore` that keeps everything in memory.
///
/// Two jobs. It is the environment's default, so a `#Preview` renders download
/// state without writing to the device. And it is what the app falls back to if
/// Application Support cannot be prepared at launch — downloading then quietly
/// achieves nothing for that run, which is a better failure than an app that
/// will not start.
final class InMemoryOfflineChapterStore: OfflineChapterStore, @unchecked Sendable {
    let chapterLimit: Int

    private let lock = NSLock()
    private var records: [DownloadedChapterID: DownloadedChapter] = [:]
    private var pages: [DownloadedChapterID: [URL: Data]] = [:]

    init(chapterLimit: Int = OfflineDownloadLimits.maxChapters) {
        self.chapterLimit = chapterLimit
    }

    func downloadedChapters() -> [DownloadedChapter] {
        lock.withLock { Array(records.values) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func downloadedChapter(_ id: DownloadedChapterID) -> DownloadedChapter? {
        lock.withLock { records[id] }
    }

    @discardableResult
    func admit(
        _ chapter: DownloadedChapter,
        protecting: DownloadedChapterID?
    ) throws -> DownloadedChapterID? {
        try lock.withLock {
            guard records[chapter.id] == nil else { return nil }

            var evicted: DownloadedChapterID?
            if records.count >= chapterLimit {
                guard
                    let victim = records.values
                        .filter({ $0.id != protecting })
                        .min(by: { $0.startedAt < $1.startedAt })?
                        .id
                else { throw OfflineDownloadError.chapterLimitReached }
                records[victim] = nil
                pages[victim] = nil
                evicted = victim
            }

            records[chapter.id] = chapter
            return evicted
        }
    }

    func update(_ chapter: DownloadedChapter) throws {
        try lock.withLock {
            guard records[chapter.id] != nil else {
                throw OfflineDownloadError.unknownChapter
            }
            records[chapter.id] = chapter
        }
    }

    func hasPage(_ url: URL, of chapterID: DownloadedChapterID) -> Bool {
        lock.withLock { pages[chapterID]?[url] != nil }
    }

    func writePage(_ data: Data, for url: URL, of chapterID: DownloadedChapterID) throws {
        lock.withLock { pages[chapterID, default: [:]][url] = data }
    }

    func pageData(for url: URL) -> Data? {
        lock.withLock {
            for chapterPages in pages.values {
                if let data = chapterPages[url] { return data }
            }
            return nil
        }
    }

    func sizeOnDisk(of chapterID: DownloadedChapterID) -> Int64 {
        lock.withLock {
            Int64(pages[chapterID]?.values.reduce(0) { $0 + $1.count } ?? 0)
        }
    }

    func delete(_ chapterID: DownloadedChapterID) throws {
        lock.withLock {
            records[chapterID] = nil
            pages[chapterID] = nil
        }
    }
}

// MARK: - Environment injection

private struct OfflineChapterStoreKey: EnvironmentKey {
    /// Offline-safe default, like `ComicRepositoryKey`'s: a `#Preview` shows
    /// download affordances without touching the device's storage. The app
    /// installs the real one in `vista_comicApp`.
    static let defaultValue: any OfflineChapterStore = InMemoryOfflineChapterStore()
}

extension EnvironmentValues {
    /// Where the current view tree's downloaded chapters live.
    var offlineChapterStore: any OfflineChapterStore {
        get { self[OfflineChapterStoreKey.self] }
        set { self[OfflineChapterStoreKey.self] = newValue }
    }
}
