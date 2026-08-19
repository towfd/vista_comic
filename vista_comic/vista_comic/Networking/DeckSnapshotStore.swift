//
//  DeckSnapshotStore.swift
//  vista_comic
//
//  The last successful `GET /cards` response, kept so "you have already
//  collected this" can be answered with no connection.
//
//  **Raw response bytes, not models**, for the reason `CatalogSnapshotStore`
//  gives: `LearningCard` is `Decodable` only, and keeping it that way is worth
//  more than the convenience of storing objects. Re-encoding would need an
//  `Encodable` conformance, a second representation of every field, and a
//  migration story of its own the first time the backend adds one.
//
//  **Not the same thing as a deck.** Nothing here decides what is collected; it
//  only remembers what the server last said. The matching lives in
//  `SelectionActions.alreadyCollected`, which is pure and takes cards.
//

import Foundation

/// The last good `GET /cards` response, as bytes.
///
/// Written by `APIStudyRepository` on success, read by it again when something
/// asks what is known locally. Only a response that genuinely arrived and
/// genuinely decoded is ever stored.
protocol DeckSnapshotStore: Sendable {
    func store(_ data: Data)
    func data() -> Data?
}

/// The store the app runs on: one small file under Application Support, beside
/// the catalog snapshots and excluded from backup for the same reasons.
///
/// One file rather than a directory: unlike the catalog, there is exactly one
/// response to remember. The reader has one vocabulary.
final class FileDeckSnapshotStore: DeckSnapshotStore, @unchecked Sendable {
    private let file: URL
    private let fileManager = FileManager.default

    init(root: URL? = nil) throws {
        var resolvedRoot = try root ?? Self.defaultRoot()
        try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resolvedRoot.setResourceValues(values)
        self.file = resolvedRoot.appendingPathComponent("deck.json")
    }

    static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Deck", isDirectory: true)
    }

    func store(_ data: Data) {
        // Best-effort by design, like every other snapshot here: a snapshot
        // that cannot be written costs the reader a marker, never the request
        // that succeeded.
        try? data.write(to: file, options: .atomic)
    }

    func data() -> Data? {
        try? Data(contentsOf: file)
    }
}

/// An in-memory store for tests, previews, and the app's launch fallback —
/// mirroring `InMemoryCatalogSnapshotStore`'s role. With nowhere to keep the
/// snapshot, the marker simply needs a connection, which is no worse than not
/// having the feature.
final class InMemoryDeckSnapshotStore: DeckSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    init(seed: Data? = nil) {
        self.stored = seed
    }

    func store(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        stored = data
    }

    func data() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
