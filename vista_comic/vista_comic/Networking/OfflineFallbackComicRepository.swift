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
//  - `rescan()` passes straight through. Rescanning is a request to the server
//    by definition.
//  - `saveProgress` queues what it could not send (ticket 03), and any request
//    that succeeds is the cue to try the queue again.
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
    /// Reading positions the backend has not taken yet (ticket 03).
    let pending: any PendingProgressStore
    /// Sends them, one at a time, and never twice at once.
    private let flusher: PendingProgressFlusher
    /// Told which URLs are comic covers (ticket 07). It is told here because
    /// this is the one place a decoded library response passes through on both
    /// the live path and the stored one, and because the answer is a fact about
    /// the catalog rather than about any screen.
    let covers: (any CoverCache)?

    init(
        wrapping inner: any ComicRepository,
        snapshots: any CatalogSnapshotStore,
        chapters: any OfflineChapterStore,
        pending: any PendingProgressStore = InMemoryPendingProgressStore(),
        covers: (any CoverCache)? = nil
    ) {
        self.inner = inner
        self.snapshots = snapshots
        self.chapters = chapters
        self.pending = pending
        self.covers = covers
        self.flusher = PendingProgressFlusher(store: pending) { progress in
            // Sent through the *inner* repository, so a flush cannot re-enter
            // this decorator and queue what it is in the middle of sending.
            try await inner.saveProgress(
                comicID: progress.comicID,
                chapterID: progress.chapterID,
                lastPage: progress.lastPage
            )
        }
    }

    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    func library() async throws -> [Comic] {
        // Before, not after. The library is where reading progress is *shown* —
        // 繼續閱讀, the read badges, "last read" — so catching the server up
        // first is the difference between landing and seeing where you got to,
        // and landing, seeing yesterday, and having to refresh again.
        //
        // It costs nothing when there is nothing queued, and when the reader is
        // still offline it costs one request that fails the way every other
        // request is failing anyway.
        await flusher.flush()

        let comics: [Comic]
        do {
            comics = try await inner.library()
        } catch {
            comics = try replay([Comic].self, from: .library, after: error)
        }
        // On both paths, since a replayed library is the same library — and a
        // reader who has been offline since launch should still have the covers
        // they scrolled past yesterday served rather than pruned.
        covers?.setKnownCovers(comics.compactMap(\.coverURL))
        return comics
    }

    func comic(id: String) async throws -> Comic {
        // Same reason: this screen shows a read badge per chapter.
        await flusher.flush()
        do {
            // A live response is fresher than anything held here, and the queue
            // was just flushed in front of it, so it is returned untouched.
            return try await inner.comic(id: id)
        } catch {
            let stored = try replay(Comic.self, from: .comic(id: id), after: error)
            return withPendingProgress(stored)
        }
    }

    /// The one request a stored response cannot answer.
    ///
    /// A completed download's record carries the ordered page URLs, which is the
    /// only thing the Reader actually needs — and unlike a stored response, it
    /// is a promise about the device rather than a memory of the server.
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        // And again: this request *is* the resume position. A chapter opened
        // just after reconnecting must not reopen at the page the server last
        // heard about.
        await flusher.flush()
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
                // The server holds progress and is not answering, so the queue
                // answers instead: where this reader got to offline is exactly
                // what is sitting in it, unsent. `nil` when they have not opened
                // the chapter offline yet, which starts them at the top as
                // before.
                lastReadPage: pending.progress(for: id)?.lastPage
            )
        }
    }

    func rescan() async throws {
        try await inner.rescan()
    }

    /// Keeps the write's existing contract exactly — it never interrupts
    /// reading and never surfaces an error — and changes only what happens to
    /// the position it could not send: it is queued rather than discarded.
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        do {
            try await inner.saveProgress(comicID: comicID, chapterID: chapterID, lastPage: lastPage)
        } catch {
            guard Self.isUnreachable(error) else { throw error }
            pending.enqueue(
                PendingProgress(comicID: comicID, chapterID: chapterID, lastPage: lastPage)
            )
            // Not rethrown: the position is not lost, so nothing failed in any
            // sense the caller could act on.
            return
        }

        // A write that got through is the clearest evidence there is that the
        // backend is reachable, so it is the natural moment to try the rest —
        // in the background, since the reader is mid-page and waiting on
        // nothing.
        Task { [flusher] in await flusher.flush() }
    }

    // MARK: - What the queue knows

    /// Re-states a stored chapter list in terms of the positions that have not
    /// been sent yet (ticket 08).
    ///
    /// A stored response is a faithful record of a moment that has since passed:
    /// it was written the last time the app was online, and the reader has been
    /// reading since. The queue is the only thing that knows that, and without
    /// this the reader finishes a chapter offline and the list still calls it
    /// unread.
    ///
    /// Applied **only** to a replayed response. A live one is fresher than
    /// anything local by definition.
    private func withPendingProgress(_ comic: Comic) -> Comic {
        let chapters = comic.chapters.map { chapter -> Chapter in
            let id = DownloadedChapterID(comicID: comic.id, chapterID: chapter.id)
            guard let queued = pending.progress(for: id) else { return chapter }
            return Chapter(
                id: chapter.id,
                number: chapter.number,
                title: chapter.title,
                pageURLs: chapter.pageURLs,
                pageCount: chapter.pageCount,
                readState: Self.readState(lastPage: queued.lastPage, pageCount: chapter.pageCount),
                lastReadPage: queued.lastPage,
                coverURL: chapter.coverURL
            )
        }

        // `lastReadAt` and `continueChapterId` are left exactly as stored. What
        // the library card shows is decided by a rule with real branching — the
        // most recent reading chapter, else the first unread, else the first —
        // and reproducing that here would be duplication rather than a mirror.
        return Comic(
            id: comic.id,
            title: comic.title,
            coverURL: comic.coverURL,
            chapters: chapters,
            chapterCount: comic.chapterCount,
            lastReadAt: comic.lastReadAt,
            continueChapterId: comic.continueChapterId
        )
    }

    /// Mirrors the backend's `progress_store.read_state` exactly: a last page at
    /// or past the page count is `read`, anything else is `reading`. (Its third
    /// case, no progress at all, cannot arise here — there would be no queued
    /// entry to ask about.)
    ///
    /// Deliberately a mirror rather than a judgement of our own. If this said
    /// `read` where the backend says `reading`, reconnecting would change the
    /// badge under the reader — worse than the stale badge this replaces,
    /// because it looks like the app changing its mind.
    static func readState(lastPage: Int, pageCount: Int) -> ReadState {
        lastPage >= pageCount ? .read : .reading
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


// MARK: - Sending what is queued

/// Drains `PendingProgressStore`, one entry at a time, never twice at once.
///
/// An actor because "am I already flushing?" is the only state it has, and two
/// flushes racing would send the same position twice and — worse — could remove
/// an entry the other one had just replaced with a newer page.
actor PendingProgressFlusher {
    private let store: any PendingProgressStore
    private let send: @Sendable (PendingProgress) async throws -> Void
    private var isFlushing = false

    init(
        store: any PendingProgressStore,
        send: @escaping @Sendable (PendingProgress) async throws -> Void
    ) {
        self.store = store
        self.send = send
    }

    /// Sends everything waiting, oldest first, dropping each entry **only**
    /// once the server has taken it.
    ///
    /// Stops at the first entry that cannot be sent rather than working through
    /// the rest: the overwhelmingly likely reason is that the connection is
    /// still not there, and the queue exists precisely so that nothing has to be
    /// hurried.
    ///
    /// The exception is a server that *refuses* an entry — a chapter that no
    /// longer exists, say. That will never be accepted however many times it is
    /// offered, and leaving it at the head would wedge every later position
    /// behind it forever, so it is dropped and the flush carries on.
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
