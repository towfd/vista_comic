//
//  CatalogSnapshotStore.swift
//  vista_comic
//
//  The last successful catalog responses, kept so the library still renders
//  with no connection (`offline-download` ticket 02).
//
//  **Raw response bytes, not models.** `Comic` and `Chapter` are `Decodable`
//  only, and keeping them that way is worth more than the convenience of
//  storing objects: re-encoding would need an `Encodable` conformance on the
//  display models, a second representation of every field, and a migration
//  story of its own the first time the backend adds one. Bytes need none of
//  that — what came back is what is replayed.
//

import CryptoKit
import Foundation

/// Which catalog response a snapshot is of.
enum CatalogSnapshot: Hashable, Sendable {
    /// `GET /comics` — the library list.
    case library
    /// `GET /comics/{id}` — one comic with its chapters.
    case comic(id: String)
}

/// Keeps the bytes of the last successful response for each catalog request.
///
/// Written by `APIComicRepository` on success, read by
/// `OfflineFallbackComicRepository` when the network is unreachable. Those are
/// its only two callers, and the asymmetry is deliberate: only a response that
/// genuinely arrived and genuinely decoded is ever stored.
protocol CatalogSnapshotStore: Sendable {
    func store(_ data: Data, for snapshot: CatalogSnapshot)
    func data(for snapshot: CatalogSnapshot) -> Data?
}

/// The store the app runs on: one small file per request under Application
/// Support, beside the downloaded chapters and excluded from backup for the
/// same reasons.
///
/// Deliberately **not** bounded or evicted. A snapshot is a few kilobytes of
/// JSON per comic the reader has actually opened, against 5–20 MB for a single
/// downloaded chapter, and it is the thing that makes those chapters reachable.
final class FileCatalogSnapshotStore: CatalogSnapshotStore, @unchecked Sendable {
    private let root: URL
    private let fileManager = FileManager.default

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
            .appendingPathComponent("OfflineCatalog", isDirectory: true)
    }

    func store(_ data: Data, for snapshot: CatalogSnapshot) {
        // A snapshot that cannot be written costs the reader nothing today and
        // the offline library tomorrow — never the request that succeeded, so
        // this is best-effort by design.
        try? data.write(to: file(for: snapshot), options: .atomic)
    }

    func data(for snapshot: CatalogSnapshot) -> Data? {
        try? Data(contentsOf: file(for: snapshot))
    }

    private func file(for snapshot: CatalogSnapshot) -> URL {
        root.appendingPathComponent(Self.digest(of: snapshot))
    }

    /// Digested rather than named from the comic id, which is a
    /// server-generated string: a path separator arriving inside one would
    /// otherwise write outside the root.
    private static func digest(of snapshot: CatalogSnapshot) -> String {
        let key: String
        switch snapshot {
        case .library: key = "library"
        case .comic(let id): key = "comic\u{0}\(id)"
        }
        return SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// An in-memory snapshot store for previews and for the app's launch fallback,
/// mirroring `InMemoryOfflineChapterStore`'s role.
final class InMemoryCatalogSnapshotStore: CatalogSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [CatalogSnapshot: Data] = [:]

    init() {}

    func store(_ data: Data, for snapshot: CatalogSnapshot) {
        lock.withLock { snapshots[snapshot] = data }
    }

    func data(for snapshot: CatalogSnapshot) -> Data? {
        lock.withLock { snapshots[snapshot] }
    }
}
