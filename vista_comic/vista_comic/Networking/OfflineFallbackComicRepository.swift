//
//  OfflineFallbackComicRepository.swift
//  vista_comic
//
//  What the app reads its catalog through once downloads exist
//  (`offline-download` ticket 02): the live repository, plus an answer for the
//  case where the network cannot give one.
//
//  **A decorator, so no screen changes.** 書庫, the chapter list and the Reader
//  keep depending on `ComicRepository` exactly as they do today, and none of
//  them gains an offline code path — which is the point, because a second path
//  is a second thing that can be wrong. The protocol is untouched.
//
//  Three requests, three different answers:
//
//  - `library()` and `comic(id:)` replay the last successful response's bytes,
//    so browsing still works and the download markers are still there.
//  - `readerChapter` replays nothing. It answers from a **completed** chapter
//    record, which is exactly what that record was built to make possible, and
//    a stored response would be the wrong answer — it would hand the Reader a
//    page list for a chapter whose pages are not on the device.
//  - `rescan()` and `saveProgress` pass straight through. Rescanning is a
//    request to the server by definition, and progress is best-effort today;
//    queueing it for later is ticket 03.
//

import Foundation

/// Failures that mean "this is not something the device can answer", as opposed
/// to "the request failed".
enum OfflineReadError: Error, Equatable {
    /// The network is unreachable and this chapter is not downloaded — or is
    /// only partly downloaded, which is the same thing to a reader.
    ///
    /// Distinguishable on purpose: the Reader says so in plain words instead of
    /// showing the generic connection error, which would leave the reader
    /// guessing whether the app, the server or their signal is at fault.
    case chapterNotAvailableOffline
}

struct OfflineFallbackComicRepository: ComicRepository {
    let inner: any ComicRepository
    let snapshots: any CatalogSnapshotStore
    let chapters: any OfflineChapterStore

    init(
        wrapping inner: any ComicRepository,
        snapshots: any CatalogSnapshotStore,
        chapters: any OfflineChapterStore
    ) {
        self.inner = inner
        self.snapshots = snapshots
        self.chapters = chapters
    }

    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    func library() async throws -> [Comic] {
        do {
            return try await inner.library()
        } catch {
            return try replay([Comic].self, from: .library, after: error)
        }
    }

    func comic(id: String) async throws -> Comic {
        do {
            return try await inner.comic(id: id)
        } catch {
            return try replay(Comic.self, from: .comic(id: id), after: error)
        }
    }

    /// The one request a stored response cannot answer.
    ///
    /// A completed download's record carries the ordered page URLs, which is the
    /// only thing the Reader actually needs — and unlike a stored response, it
    /// is a promise about the device rather than a memory of the server.
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        do {
            return try await inner.readerChapter(comicID: comicID, chapterID: chapterID)
        } catch {
            guard Self.isUnreachable(error) else { throw error }

            let id = DownloadedChapterID(comicID: comicID, chapterID: chapterID)
            // Completed, not merely present: a chapter missing its last twenty
            // pages would open, read beautifully, and then stop — the worst
            // moment to find out, since it is usually the moment there is no
            // connection to fix it with.
            guard let record = chapters.downloadedChapter(id), record.isComplete else {
                throw OfflineReadError.chapterNotAvailableOffline
            }

            return Chapter(
                id: record.chapterID,
                number: record.chapterNumber,
                title: record.chapterTitle,
                pageURLs: record.pageURLs,
                pageCount: record.pageCount,
                // No resume position: the server holds progress, and it is not
                // answering. Reading offline therefore starts at the top for
                // now — ticket 03 gives the queued local position back here.
                lastReadPage: nil
            )
        }
    }

    func rescan() async throws {
        try await inner.rescan()
    }

    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        try await inner.saveProgress(comicID: comicID, chapterID: chapterID, lastPage: lastPage)
    }

    // MARK: - Falling back

    private func replay<T: Decodable>(
        _ type: T.Type,
        from snapshot: CatalogSnapshot,
        after networkError: any Error
    ) throws -> T {
        guard Self.isUnreachable(networkError), let data = snapshots.data(for: snapshot) else {
            throw networkError
        }
        guard let replayed = try? decoder.decode(T.self, from: data) else {
            // Stored bytes that no longer decode — an app updated across a
            // response-shape change, most likely. Surfacing the decoding failure
            // would blame the wrong thing: what the reader is actually facing is
            // that they are offline.
            throw networkError
        }
        return replayed
    }

    /// Whether the request failed because nothing could be reached, as opposed
    /// to because the server answered badly.
    ///
    /// **The fallback must not mask a live failure.** A 500, an auth rejection
    /// at the Cloudflare edge, or a response the app cannot decode all mean the
    /// server is there and something is wrong; quietly serving yesterday's
    /// library instead would look perfectly fine on screen while being silently
    /// out of date, and nothing would ever tell the reader. Only a transport
    /// failure — `URLError`, which is what airplane mode, a dead tunnel and a
    /// timeout all produce — counts as "offline".
    private static func isUnreachable(_ error: any Error) -> Bool {
        error is URLError
    }
}
