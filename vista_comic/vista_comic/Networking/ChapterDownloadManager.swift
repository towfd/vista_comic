//
//  ChapterDownloadManager.swift
//  vista_comic
//
//  The engine behind `offline-download` ticket 01: what is downloading, what is
//  queued, and what the chapter list shows for each row.
//
//  A concrete `@Observable` type rather than a protocol, deliberately: it
//  depends only on `OfflineChapterStore` and `ComicRepository`, both of which
//  are already seams, so a test or a preview drives its whole observable state
//  by substituting those. Adding a third protocol would buy nothing.
//
//  **Chapters download one at a time.** Not an arbitrary policy: four page
//  fetches at once is the limit, and two chapters running concurrently would be
//  eight. Queueing is therefore where "download several" (ticket 06) will plug
//  in, rather than something that has to be retrofitted around it.
//

import Foundation
import SwiftUI

/// What a chapter row shows.
///
/// Deliberately not a property of `DownloadedChapter`: a record exists only once
/// a slot is reserved, while a row has something to say about every chapter in
/// the list — including the ones that were never downloaded.
enum ChapterDownloadState: Equatable {
    case notDownloaded
    /// Queued or running. `total` is `0` until the reader endpoint has answered
    /// with the real page list, which the ring reads as "starting".
    case downloading(completed: Int, total: Int)
    /// Every page is present. The only state that means readable offline.
    case downloaded
    /// Something did not arrive. The partial chapter is kept, so retrying
    /// resumes rather than restarts.
    case failed

    /// How full the progress ring is, `0` when the page count is not yet known.
    var fraction: Double {
        guard case let .downloading(completed, total) = self, total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }
}

@MainActor
@Observable
final class ChapterDownloadManager {
    /// Chapters downloading or queued right now, and how far each has got.
    /// In-flight state only — what is finished is the store's business.
    private(set) var active: [DownloadedChapterID: ChapterDownloadState] = [:]

    /// How many of the twenty slots are in use, for the chapter list to show.
    /// Mirrored from the store for the same reason `completed` is: the store is
    /// read from `body` and therefore cannot be observable.
    private(set) var usedSlots: Int

    /// The chapter open in the Reader, which eviction must not touch. Set by the
    /// Reader, because it is the only thing that knows.
    private var openChapter: DownloadedChapterID?

    /// Completed chapters, mirrored from the store at init and kept current as
    /// downloads finish.
    ///
    /// The mirror exists because `OfflineChapterStore` is not observable — it is
    /// read from `body`, so it cannot be — and a row that learns a chapter is
    /// downloaded only when something else happens to redraw it would be
    /// telling the reader the wrong thing for as long as they stayed on screen.
    private(set) var completed: Set<DownloadedChapterID>

    private let store: any OfflineChapterStore
    private let repository: any ComicRepository
    private let downloader: ChapterPageDownloader

    /// Chapters waiting their turn, in the order they were asked for.
    private var queue: [DownloadedChapter] = []
    /// The drain loop. `nil` when there is nothing to do — downloading is not a
    /// background service, it is work with an end.
    private var runner: Task<Void, Never>?
    /// The chapter being downloaded right now, and the task doing it. Cancelling
    /// that task stops the chapter without stopping the queue.
    private var current: (id: DownloadedChapterID, task: Task<Void, Never>)?
    /// Chapters the reader cancelled, as opposed to chapters stopped by
    /// backgrounding. The two look identical from inside the download — one
    /// discards the partial chapter, the other keeps it — so the difference has
    /// to be recorded here, by whoever stopped it.
    private var cancelled: Set<DownloadedChapterID> = []

    private(set) var isPaused = false

    init(
        store: any OfflineChapterStore,
        repository: any ComicRepository,
        session: URLSession = .shared,
        clientID: String? = APIConfig.cfAccessClientID,
        clientSecret: String? = APIConfig.cfAccessClientSecret
    ) {
        self.store = store
        self.repository = repository
        self.downloader = ChapterPageDownloader(
            store: store,
            session: session,
            clientID: clientID,
            clientSecret: clientSecret
        )
        let downloaded = store.downloadedChapters()
        self.completed = Set(downloaded.filter(\.isComplete).map(\.id))
        self.usedSlots = downloaded.count
    }

    // MARK: What the Reader is holding open

    /// Tells the engine which chapter is being read, so the cap never deletes
    /// the pages out from under it. Cleared when the Reader closes.
    func readerOpened(comicID: String, chapterID: String) {
        openChapter = DownloadedChapterID(comicID: comicID, chapterID: chapterID)
    }

    func readerClosed() {
        openChapter = nil
    }

    // MARK: What a row shows

    func state(for chapterID: DownloadedChapterID) -> ChapterDownloadState {
        if let active = active[chapterID] { return active }
        if completed.contains(chapterID) { return .downloaded }
        if store.downloadedChapter(chapterID) != nil { return .failed }
        return .notDownloaded
    }

    func state(comicID: String, chapterID: String) -> ChapterDownloadState {
        state(for: DownloadedChapterID(comicID: comicID, chapterID: chapterID))
    }

    // MARK: Starting and stopping

    /// Reserves a slot for this chapter and queues it, evicting the oldest
    /// download if the device is already full.
    ///
    /// The chapter here is the *summary* the list screen holds, which carries no
    /// page URLs — those are resolved from the reader endpoint once the download
    /// starts. Its `pageCount` is enough to draw a ring in the meantime.
    ///
    /// The reader is never stopped and asked to tidy up: downloading a
    /// twenty-first chapter removes the one downloaded longest ago and proceeds.
    func download(comic: Comic, chapter: Chapter) {
        let id = DownloadedChapterID(comicID: comic.id, chapterID: chapter.id)
        guard active[id] == nil, !completed.contains(id) else { return }

        // An existing record means an interrupted download: it already holds a
        // slot and a `startedAt`, and re-admitting it must not reset either.
        let record = store.downloadedChapter(id) ?? DownloadedChapter(
            comicID: comic.id,
            comicTitle: comic.title,
            chapterID: chapter.id,
            chapterNumber: chapter.number,
            chapterTitle: chapter.title,
            pageURLs: chapter.pageURLs,
            pageCount: chapter.pageCount
        )

        do {
            let evicted = try store.admit(record, protecting: openChapter)
            if let evicted {
                // The evicted chapter is gone from the device, so every row that
                // said so has to stop saying it.
                completed.remove(evicted)
                active[evicted] = nil
            }
        } catch {
            // The device is full and everything on it is protected, which cannot
            // happen at a cap of twenty with one chapter open. Nothing is said,
            // because there is nothing the reader could usefully do about it.
            active[id] = nil
            return
        }
        usedSlots = store.downloadedChapters().count

        queue.append(record)
        // Shown as downloading from the moment it is queued: the reader tapped,
        // and a row that still says "not downloaded" until its turn comes round
        // reads as a tap that did nothing.
        active[id] = .downloading(completed: 0, total: record.pageCount)
        startRunnerIfNeeded()
    }

    /// Queues several chapters in one action (ticket 06).
    ///
    /// **Admitted one at a time, deliberately.** There is no batch admission
    /// path at all: five chapters take five slots and therefore evict exactly
    /// five, which is the semantic ticket 04 settled. Admitting a batch as a
    /// unit would be the obvious way around that, so the way is simply not
    /// built.
    ///
    /// **A selection larger than the cap is refused rather than trimmed.** It
    /// would otherwise evict its own earlier chapters as its later ones
    /// arrived — thrashing the disk to arrive at the last twenty of whatever
    /// was asked for, which is not what anyone asked for. Below that size the
    /// batch cannot eat itself at all: eviction takes the oldest download, and
    /// every chapter in the batch is newer than everything already there.
    ///
    /// Chapters already on the device are skipped, so a selection is measured
    /// by what it would actually add.
    ///
    /// - Returns: `false` when the selection is too large and nothing was
    ///   queued, so the screen can say so.
    @discardableResult
    func download(comic: Comic, chapters: [Chapter]) -> Bool {
        let wanted = chapters.filter { chapter in
            !completed.contains(DownloadedChapterID(comicID: comic.id, chapterID: chapter.id))
        }
        guard wanted.count <= store.chapterLimit else { return false }

        for chapter in wanted {
            download(comic: comic, chapter: chapter)
        }
        return true
    }

    /// Stops this chapter and discards what it had downloaded.
    ///
    /// Cancelling is the reader changing their mind, so the partial chapter goes
    /// — a half-present chapter that still occupied a slot would be the worst of
    /// both: unreadable offline, and in the way of something that is.
    func cancel(_ chapterID: DownloadedChapterID) {
        if let index = queue.firstIndex(where: { $0.id == chapterID }) {
            queue.remove(at: index)
            active[chapterID] = nil
            try? store.delete(chapterID)
            usedSlots = store.downloadedChapters().count
            return
        }

        guard current?.id == chapterID else { return }

        cancelled.insert(chapterID)
        current?.task.cancel()
    }

    /// Backgrounding stops the current chapter without giving up its slot or its
    /// pages; it goes back to the head of the queue and resumes on return.
    ///
    /// Downloading is foreground-only by design (see the spec's Out of Scope): a
    /// background `URLSession` for 60–180 tasks a chapter, re-associated after
    /// termination, is comparable in size to the rest of the feature.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        current?.task.cancel()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        startRunnerIfNeeded()
    }

    /// Test seam: returns once the queue is empty and nothing is running.
    /// Downloading has an end, so waiting for it is a legitimate thing to do.
    func waitUntilIdle() async {
        while let runner {
            _ = await runner.value
        }
    }

    // MARK: The queue

    private func startRunnerIfNeeded() {
        guard runner == nil, !isPaused, !queue.isEmpty else { return }
        runner = Task { [weak self] in
            guard let self else { return }
            await drainQueue()
        }
    }

    private func drainQueue() async {
        while !queue.isEmpty, !isPaused {
            let record = queue.removeFirst()
            let task = Task { [weak self] in
                guard let self else { return }
                await run(record)
            }
            current = (record.id, task)
            // Returns when the chapter is finished, failed, or cancelled — a
            // cancelled *child* leaves this loop free to take the next chapter,
            // which is why the child exists rather than cancelling the runner.
            await task.value
            current = nil
        }
        runner = nil
    }

    private func run(_ record: DownloadedChapter) async {
        var record = record
        let id = record.id

        do {
            if record.pageURLs.isEmpty {
                // The only source of a chapter's ordered page URLs. Stored
                // before a single page is fetched, because without it the bytes
                // cannot be reassembled into a chapter later.
                let chapter = try await repository.readerChapter(
                    comicID: id.comicID,
                    chapterID: id.chapterID
                )
                record.pageURLs = chapter.pageURLs
                record.pageCount = chapter.pageURLs.count
                try store.update(record)
            }

            let total = record.pageURLs.count
            // Keeps whatever the ring already showed: a chapter resuming after
            // being paused must not appear to start over.
            if case let .downloading(alreadyStored, _) = active[id] {
                active[id] = .downloading(completed: min(alreadyStored, total), total: total)
            } else {
                active[id] = .downloading(completed: 0, total: total)
            }

            try await downloader.download(pageURLs: record.pageURLs, of: id) { [weak self] stored in
                Task { @MainActor in
                    self?.report(stored, of: total, for: id)
                }
            }

            // Complete is a property of the disk, not of the loop finishing.
            guard record.pageURLs.allSatisfy({ store.hasPage($0, of: id) }) else {
                throw OfflineDownloadError.incompleteChapter
            }
            record.isComplete = true
            try store.update(record)

            completed.insert(id)
            active[id] = nil
        } catch {
            finish(id, record: record, after: error)
        }
    }

    /// Progress arrives from the download's own task, so it is reported through
    /// a hop back onto the main actor and can land out of order. Taking the
    /// larger value keeps the ring from going backwards.
    private func report(_ stored: Int, of total: Int, for chapterID: DownloadedChapterID) {
        guard case let .downloading(current, _) = active[chapterID] else { return }
        active[chapterID] = .downloading(completed: max(current, stored), total: total)
    }

    /// Which of the three ways a download can stop this was, and what each costs.
    private func finish(_ id: DownloadedChapterID, record: DownloadedChapter, after error: any Error) {
        if cancelled.remove(id) != nil {
            active[id] = nil
            try? store.delete(id)
            usedSlots = store.downloadedChapters().count
            return
        }

        if isPaused {
            // Keeps its slot, its pages and its place at the head of the queue.
            // Nothing is discarded, so returning to the foreground costs only
            // what had not arrived.
            queue.insert(record, at: 0)
            return
        }

        active[id] = nil
    }
}

// MARK: - Environment injection

private struct ChapterDownloadManagerKey: EnvironmentKey {
    /// A manager over the preview store, so a `#Preview` of the chapter list
    /// renders download affordances — and even runs one — without touching the
    /// device's storage or the network. `vista_comicApp` installs the real one.
    @MainActor static let defaultValue = ChapterDownloadManager(
        store: InMemoryOfflineChapterStore(),
        repository: PreviewComicRepository()
    )
}

extension EnvironmentValues {
    /// The downloads the current view tree starts, watches and cancels.
    var chapterDownloads: ChapterDownloadManager {
        get { self[ChapterDownloadManagerKey.self] }
        set { self[ChapterDownloadManagerKey.self] = newValue }
    }
}
