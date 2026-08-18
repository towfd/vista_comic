//
//  CoverCache.swift
//  vista_comic
//
//  Comic covers, kept on the device so 書庫 looks like 書庫 with no connection
//  (`offline-download` ticket 07).
//
//  **A second store, and deliberately not the first.** `OfflineChapterStore`
//  holds what the reader chose to download, and the rule that only the download
//  engine writes to it is what keeps the 已下載 list, the cap and the device in
//  agreement. Nothing here counts against any of that: a cover is not a
//  download, it is not listed, and it does not occupy a slot. Keeping the two
//  apart is what lets this one be written on a read without making a single
//  statement the app makes about downloads untrue.
//
//  **Comic covers only.** One image per comic, so the cache is exactly as large
//  as the library and grows only when the library does. Chapter thumbnails are
//  one per chapter — 3,000+ at this library's size — and are the reason a
//  general "cache what you saw" would have needed a byte budget, an eviction
//  policy and a ticket of its own.
//

import CryptoKit
import Foundation

/// Keeps the bytes of comic covers, and knows which URLs are allowed to be one.
///
/// The membership question is the interesting half. The image cache has no
/// opinion about what an image depicts — one instance and one budget serve
/// pages and covers alike, on purpose — so it cannot be the thing that decides.
/// The catalog decides: every `Comic.coverURL` in a library response is a comic
/// cover, and nothing else is.
protocol CoverCache: Sendable {
    /// Declares the complete set of comic covers, from a library response.
    ///
    /// Also the eviction rule: anything held that is not in `urls` is dropped,
    /// so a comic leaving the library stops costing anything and the cache
    /// stays bounded by the library's own size with no budget to tune.
    func setKnownCovers(_ urls: [URL])

    /// The bytes of a cover already on the device, or `nil`.
    func data(for url: URL) -> Data?

    /// Keeps `data` if — and only if — `url` is one of the known covers.
    ///
    /// Called with every image the app fetches, which is why the filtering
    /// lives in here rather than at the call site: the caller genuinely does
    /// not know what it just downloaded.
    func storeIfKnownCover(_ data: Data, for url: URL)
}

/// The cover cache the app runs on: one file per cover under Application
/// Support, beside the downloaded chapters and the catalog snapshots, and
/// excluded from backup for the same reason.
final class FileCoverCache: CoverCache, @unchecked Sendable {
    private let root: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    /// Digest → URL for everything the catalog currently calls a cover.
    /// Digests, because that is what the filenames are, and pruning compares
    /// filenames.
    private var known: [String: URL] = [:]

    init(root: URL? = nil) throws {
        var resolvedRoot = try root ?? Self.defaultRoot()
        try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resolvedRoot.setResourceValues(values)
        self.root = resolvedRoot
    }

    static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("OfflineCovers", isDirectory: true)
    }

    func setKnownCovers(_ urls: [URL]) {
        let known = Dictionary(
            urls.map { (Self.digest(of: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        lock.withLock { self.known = known }
        prune(keeping: Set(known.keys))
    }

    func data(for url: URL) -> Data? {
        // Not gated on membership: a cover fetched before the catalog was
        // decoded is still that comic's cover, and refusing to serve a file
        // that is sitting right there would be pedantry rather than safety.
        try? Data(contentsOf: file(for: url))
    }

    func storeIfKnownCover(_ data: Data, for url: URL) {
        let digest = Self.digest(of: url)
        guard lock.withLock({ known[digest] != nil }) else { return }
        // Best-effort: a cover that cannot be written costs a placeholder the
        // next time the reader is offline, and never the image on screen now.
        try? data.write(to: root.appendingPathComponent(digest), options: .atomic)
    }

    /// Removes every file that is not one of `digests`.
    private func prune(keeping digests: Set<String>) {
        let files = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where !digests.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func file(for url: URL) -> URL {
        root.appendingPathComponent(Self.digest(of: url))
    }

    private static func digest(of url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// An in-memory cover cache for previews and for the app's launch fallback,
/// mirroring the other two stores' doubles.
final class InMemoryCoverCache: CoverCache, @unchecked Sendable {
    private let lock = NSLock()
    private var known: Set<URL> = []
    private var covers: [URL: Data] = [:]

    init() {}

    func setKnownCovers(_ urls: [URL]) {
        lock.withLock {
            known = Set(urls)
            covers = covers.filter { known.contains($0.key) }
        }
    }

    func data(for url: URL) -> Data? {
        lock.withLock { covers[url] }
    }

    func storeIfKnownCover(_ data: Data, for url: URL) {
        lock.withLock {
            guard known.contains(url) else { return }
            covers[url] = data
        }
    }
}
