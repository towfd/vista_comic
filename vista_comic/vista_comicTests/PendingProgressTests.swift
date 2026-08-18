//
//  PendingProgressTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 03: a reading position that could not
//  be sent is kept rather than discarded, and is delivered once the backend can
//  be reached again.
//
//  Driven by an inner repository that fails on demand, like ticket 02's
//  fallbacks and for the same reason: the failure is the subject, so it is
//  injected directly rather than re-enacted through a stubbed transport.
//

import Foundation
import Testing
@testable import vista_comic

/// An inner repository that records what it was asked to save and fails when
/// told to. A class, because what it recorded is the assertion.
private final class RecordingRepository: ComicRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _saveErrors: [any Error] = []
    private var _saved: [PendingProgress] = []

    var libraryError: (any Error)?
    var chapterError: (any Error)?
    var comics: [Comic] = []

    /// Errors thrown by successive `saveProgress` calls; once exhausted, saves
    /// succeed. `nil` entries succeed in place.
    func failSaves(with errors: [any Error]) {
        lock.withLock { _saveErrors = errors }
    }

    var saved: [PendingProgress] {
        lock.withLock { _saved }
    }

    func library() async throws -> [Comic] {
        if let libraryError { throw libraryError }
        return comics
    }

    func comic(id: String) async throws -> Comic {
        if let libraryError { throw libraryError }
        return Comic(id: id, title: "Alpha", coverURL: nil)
    }

    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        if let chapterError { throw chapterError }
        return Chapter(id: chapterID, number: 1, title: "One")
    }

    func rescan() async throws {}

    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        let error: (any Error)? = lock.withLock {
            guard !_saveErrors.isEmpty else { return nil }
            return _saveErrors.removeFirst()
        }
        if let error { throw error }
        lock.withLock {
            _saved.append(
                PendingProgress(comicID: comicID, chapterID: chapterID, lastPage: lastPage)
            )
        }
    }
}

@Suite("Pending reading progress")
struct PendingProgressTests {

    private static let offline = URLError(.notConnectedToInternet)
    private static let chapterID = DownloadedChapterID(comicID: "comic-1", chapterID: "chapter-1")

    private func makeRepository(
        inner: RecordingRepository,
        pending: any PendingProgressStore,
        chapters: any OfflineChapterStore = InMemoryOfflineChapterStore()
    ) -> OfflineFallbackComicRepository {
        OfflineFallbackComicRepository(
            wrapping: inner,
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: chapters,
            pending: pending
        )
    }

    private func makeDownloadedChapter() throws -> InMemoryOfflineChapterStore {
        let chapters = InMemoryOfflineChapterStore()
        try chapters.admit(
            DownloadedChapter(
                comicID: "comic-1",
                comicTitle: "Alpha",
                chapterID: "chapter-1",
                chapterNumber: 1,
                chapterTitle: "One",
                pageURLs: [URL(string: "https://example.test/page-1")!],
                pageCount: 1,
                isComplete: true
            )
        )
        return chapters
    }

    // MARK: - The queue itself

    @Test func asecondWriteForTheSameChapterReplacesTheFirst() {
        let store = InMemoryPendingProgressStore()
        store.enqueue(PendingProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 3))
        store.enqueue(PendingProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 11))

        // A whole offline session is one row per chapter, not a log of every
        // page turn — and the only position worth sending is the furthest.
        #expect(store.queued().count == 1)
        #expect(store.queued().first?.lastPage == 11)
    }

    @Test func theQueueIsBoundedAndGivesUpItsOldestEntry() {
        let store = InMemoryPendingProgressStore(limit: 2)
        store.enqueue(PendingProgress(comicID: "c", chapterID: "one", lastPage: 1, queuedAt: Date(timeIntervalSince1970: 100)))
        store.enqueue(PendingProgress(comicID: "c", chapterID: "two", lastPage: 2, queuedAt: Date(timeIntervalSince1970: 200)))
        store.enqueue(PendingProgress(comicID: "c", chapterID: "three", lastPage: 3, queuedAt: Date(timeIntervalSince1970: 300)))

        // Storage the reader never asked for and cannot see must not be able to
        // grow without a limit.
        #expect(store.queued().map(\.chapterID) == ["two", "three"])
    }

    @Test func theQueueSurvivesRelaunching() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-progress-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try FilePendingProgressStore(root: root)
        store.enqueue(PendingProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 7))

        // Closing the app on the plane is not throwing the session away.
        let relaunched = try FilePendingProgressStore(root: root)

        #expect(relaunched.progress(for: Self.chapterID)?.lastPage == 7)
    }

    // MARK: - Queueing rather than discarding

    @Test func aWriteThatCannotReachTheBackendIsQueuedRatherThanLost() async throws {
        let inner = RecordingRepository()
        inner.failSaves(with: [Self.offline])
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending)

        // No error surfaces: the position is not lost, so nothing failed in any
        // sense the reader could act on.
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 42)

        #expect(pending.progress(for: Self.chapterID)?.lastPage == 42)
    }

    @Test func aServerThatRefusesTheWriteIsNotTreatedAsBeingOffline() async throws {
        let inner = RecordingRepository()
        inner.failSaves(with: [APIError.httpStatus(500)])
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending)

        // The backend was reached. Queueing would be claiming otherwise, and
        // the reader never sees this error either way.
        await #expect(throws: APIError.self) {
            try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 42)
        }
        #expect(pending.queued().isEmpty)
    }

    // MARK: - Catching up

    @Test func theQueueIsDeliveredOnTheNextSuccessfulRequest() async throws {
        let inner = RecordingRepository()
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending)

        // A flight: two chapters read with nothing reachable.
        inner.failSaves(with: [Self.offline, Self.offline])
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 30)
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-2", lastPage: 12)
        #expect(pending.queued().count == 2)

        // Landing: the library is the first thing the app asks for.
        _ = try await repository.library()

        #expect(inner.saved.map(\.chapterID) == ["chapter-1", "chapter-2"])
        #expect(inner.saved.map(\.lastPage) == [30, 12])
        #expect(pending.queued().isEmpty)
    }

    @Test func entriesAreDroppedOnlyOnceTheServerHasTakenThem() async throws {
        let inner = RecordingRepository()
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending)

        inner.failSaves(with: [Self.offline, Self.offline])
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 30)

        // Still unreachable when the flush is attempted: the second failure is
        // the flush's own send.
        _ = try await repository.library()

        #expect(pending.progress(for: Self.chapterID)?.lastPage == 30)
        #expect(inner.saved.isEmpty)
    }

    @Test func anEntryTheServerRefusesIsDroppedRatherThanWedgingTheQueue() async throws {
        let inner = RecordingRepository()
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending)

        pending.enqueue(PendingProgress(comicID: "comic-1", chapterID: "gone", lastPage: 5, queuedAt: Date(timeIntervalSince1970: 100)))
        pending.enqueue(PendingProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 9, queuedAt: Date(timeIntervalSince1970: 200)))
        // The chapter no longer exists: offering it again will never work, and
        // leaving it at the head would hold every later position behind it.
        inner.failSaves(with: [APIError.httpStatus(404)])

        _ = try await repository.library()

        #expect(inner.saved.map(\.chapterID) == ["chapter-1"])
        #expect(pending.queued().isEmpty)
    }

    @Test func aChapterOpenedOfflineResumesWhereTheReaderActuallyGotTo() async throws {
        let inner = RecordingRepository()
        // Consistently offline: the chapter request fails, and so does the
        // flush that runs in front of it — which is what leaves the position in
        // the queue for the fallback to read.
        inner.chapterError = Self.offline
        inner.libraryError = Self.offline
        inner.failSaves(with: [Self.offline])
        let pending = InMemoryPendingProgressStore()
        pending.enqueue(PendingProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 18))
        let repository = makeRepository(
            inner: inner,
            pending: pending,
            chapters: try makeDownloadedChapter()
        )

        let chapter = try await repository.readerChapter(comicID: "comic-1", chapterID: "chapter-1")

        // The server holds progress and is not answering, so the unsent queue is
        // the only thing that knows — and it does.
        #expect(chapter.lastReadPage == 18)
    }

    // MARK: - The two stores stay apart

    @Test func evictingADownloadedChapterLeavesItsQueuedPositionAlone() async throws {
        let inner = RecordingRepository()
        let chapters = try makeDownloadedChapter()
        let pending = InMemoryPendingProgressStore()
        let repository = makeRepository(inner: inner, pending: pending, chapters: chapters)

        inner.failSaves(with: [Self.offline])
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 22)

        // The cap reclaiming the chapter must not also throw away where the
        // reader got to in it — the two have different lifetimes on purpose.
        try chapters.delete(Self.chapterID)

        #expect(pending.progress(for: Self.chapterID)?.lastPage == 22)

        // And delivering the position leaves downloaded content alone.
        _ = try await repository.library()
        #expect(pending.queued().isEmpty)
        #expect(chapters.downloadedChapters().isEmpty)
    }
}
