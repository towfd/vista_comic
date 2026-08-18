//
//  ChapterDownloadTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 01's engine: fetching a chapter's
//  pages, resuming one that was interrupted, cancelling one that is no longer
//  wanted, and refusing to go past the cap.
//
//  Asserts on what the outside world observes — which URLs were requested, how
//  many at once, what the headers carried, what ended up on disk — never on how
//  the queue is shaped internally.
//
//  The store is the real file-backed one, pointed at a temporary directory, so
//  these exercise the same code the device runs. Nothing here may touch the real
//  Application Support path.
//

import Foundation
import Testing
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it serves a per-URL body
/// and status, optionally after a delay so several fetches are genuinely in
/// flight at once, and records every request it sees.
///
/// File-private and not shared with the other suites' identically-shaped stubs,
/// for the reason their comments give: static state raced when it was shared,
/// since Swift Testing may run different `@Suite`s in parallel with each other.
/// Its statics are lock-guarded because this one is written from several
/// concurrent loading threads — that concurrency is the point of one of the
/// tests below.
private final class DownloadStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bodies: [URL: Data] = [:]
    private static var statuses: [URL: Int] = [:]
    private static var responseDelay: TimeInterval = 0
    private static var recordedRequests: [URLRequest] = []
    private static var loadsInProgress = 0
    private static var peakLoadsInProgress = 0

    static func reset() {
        lock.withLock {
            bodies = [:]
            statuses = [:]
            responseDelay = 0
            recordedRequests = []
            loadsInProgress = 0
            peakLoadsInProgress = 0
        }
    }

    static func serve(_ body: Data, for url: URL, status: Int = 200) {
        lock.withLock {
            bodies[url] = body
            statuses[url] = status
        }
    }

    /// Holds every response back, so the number of fetches alive at one moment
    /// is observable rather than a matter of timing luck.
    static func setDelay(_ seconds: TimeInterval) {
        lock.withLock { responseDelay = seconds }
    }

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    /// Forgets what has been requested so far, keeping the served bodies. Lets
    /// a test ask "what was requested *from here on*", which is a sharper
    /// question than a running total when the interesting event is in the
    /// middle.
    static func clearRequests() {
        lock.withLock { recordedRequests = [] }
    }

    static func requestCount(for url: URL) -> Int {
        lock.withLock { recordedRequests.filter { $0.url == url }.count }
    }

    /// The most requests that were ever loading at the same moment.
    static var peakConcurrentLoads: Int {
        lock.withLock { peakLoadsInProgress }
    }

    /// Guards against a delayed response landing after the request was
    /// cancelled, and against counting one load as finished twice.
    private let settled = NSLock()
    private var hasSettled = false

    private func settleOnce() -> Bool {
        settled.withLock {
            if hasSettled { return false }
            hasSettled = true
            return true
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let delay: TimeInterval = Self.lock.withLock {
            Self.recordedRequests.append(request)
            Self.loadsInProgress += 1
            Self.peakLoadsInProgress = max(Self.peakLoadsInProgress, Self.loadsInProgress)
            return Self.responseDelay
        }

        let respond = { [weak self] in
            guard let self, self.settleOnce() else { return }
            Self.lock.withLock { Self.loadsInProgress -= 1 }

            let status = Self.lock.withLock { Self.statuses[url] ?? 200 }
            let body = Self.lock.withLock { Self.bodies[url] ?? Data() }
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {
        guard settleOnce() else { return }
        Self.lock.withLock { Self.loadsInProgress -= 1 }
    }
}

/// The chapter list holds a *summary*, which carries no page URLs — the reader
/// endpoint is their only source, so the engine has to ask for them. This is
/// that endpoint.
private struct StubComicRepository: ComicRepository {
    let chapter: Chapter

    func library() async throws -> [Comic] { [] }
    func comic(id: String) async throws -> Comic {
        Comic(id: id, title: "Alpha", coverURL: nil)
    }
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        chapter
    }
    func rescan() async throws {}
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {}
}

@MainActor
@Suite("Chapter downloads", .serialized)
struct ChapterDownloadTests {

    // MARK: - Fixtures

    private static let comic = Comic(id: "comic-1", title: "Alpha", coverURL: nil)

    private func pageURLs(_ count: Int) -> [URL] {
        (1...count).map { URL(string: "https://example.test/media/comic-1/chapter-1/page-\($0).jpg")! }
    }

    /// What the chapter list holds: a page count, and no pages.
    private func summary(pageCount: Int) -> Chapter {
        Chapter(id: "chapter-1", number: 1, title: "One", pageCount: pageCount)
    }

    private var chapterID: DownloadedChapterID {
        DownloadedChapterID(comicID: "comic-1", chapterID: "chapter-1")
    }

    private func makeStore(chapterLimit: Int = OfflineDownloadLimits.maxChapters) throws -> (FileOfflineChapterStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-download-tests-\(UUID().uuidString)", isDirectory: true)
        return (try FileOfflineChapterStore(root: root, chapterLimit: chapterLimit), root)
    }

    private func makeManager(
        store: any OfflineChapterStore,
        pages: [URL],
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> ChapterDownloadManager {
        DownloadStubURLProtocol.reset()
        for page in pages {
            DownloadStubURLProtocol.serve(Data("bytes of \(page.lastPathComponent)".utf8), for: page)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadStubURLProtocol.self]

        return ChapterDownloadManager(
            store: store,
            repository: StubComicRepository(
                chapter: Chapter(id: "chapter-1", number: 1, title: "One", pageURLs: pages)
            ),
            session: URLSession(configuration: configuration),
            clientID: clientID,
            clientSecret: clientSecret
        )
    }

    /// Polls until `condition` holds, so a test waits for the state it cares
    /// about rather than for a duration someone guessed.
    private func waitUntil(
        _ condition: () -> Bool,
        within timeout: Duration = .seconds(5)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Downloading

    @Test func downloadingStoresEveryPageAndMarksTheChapterDownloaded() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(5)
        let manager = makeManager(store: store, pages: pages)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .downloaded)
        for page in pages {
            #expect(store.hasPage(page, of: chapterID))
        }
        // The record is what makes the bytes readable later, so the page list it
        // learned from the reader endpoint has to be what was stored.
        #expect(store.downloadedChapter(chapterID)?.pageURLs == pages)
        #expect(store.downloadedChapter(chapterID)?.isComplete == true)
    }

    @Test func anInterruptedDownloadOnlyFetchesThePagesItIsMissing() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(4)
        let manager = makeManager(store: store, pages: pages)

        // What an interrupted download leaves behind: a slot, a record, and the
        // pages that had already arrived.
        try store.admit(
            DownloadedChapter(
                comicID: "comic-1",
                comicTitle: "Alpha",
                chapterID: "chapter-1",
                chapterNumber: 1,
                chapterTitle: "One",
                pageURLs: pages,
                pageCount: pages.count
            )
        )
        try store.writePage(Data("already here".utf8), for: pages[0], of: chapterID)
        try store.writePage(Data("already here".utf8), for: pages[1], of: chapterID)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .downloaded)
        #expect(DownloadStubURLProtocol.requestCount(for: pages[0]) == 0)
        #expect(DownloadStubURLProtocol.requestCount(for: pages[1]) == 0)
        #expect(DownloadStubURLProtocol.requestCount(for: pages[2]) == 1)
        #expect(DownloadStubURLProtocol.requestCount(for: pages[3]) == 1)
        // And what was already there is still there, byte for byte.
        #expect(store.hasPage(pages[0], of: chapterID))
    }

    @Test func atMostFourPageFetchesRunAtOnce() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(12)
        let manager = makeManager(store: store, pages: pages)
        // Slow enough that a fifth fetch would overlap the first four if the
        // limit were not enforced.
        DownloadStubURLProtocol.setDelay(0.05)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .downloaded)
        #expect(DownloadStubURLProtocol.peakConcurrentLoads <= 4)
        // And the limit is a ceiling, not a queue of one: fetches really do run
        // alongside each other.
        #expect(DownloadStubURLProtocol.peakConcurrentLoads > 1)
    }

    @Test func downloadsCarryTheCloudflareAccessHeaders() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(3)
        let manager = makeManager(
            store: store,
            pages: pages,
            clientID: "client-id",
            clientSecret: "client-secret"
        )

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        let requests = DownloadStubURLProtocol.requests
        #expect(requests.count == pages.count)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "client-id")
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "client-secret")
        }
    }

    // MARK: - When it does not finish

    @Test func aPageThatCannotBeFetchedLeavesTheChapterIncomplete() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(4)
        let manager = makeManager(store: store, pages: pages)
        DownloadStubURLProtocol.serve(Data(), for: pages[2], status: 404)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .failed)
        // Kept, not discarded: retrying resumes from whatever did arrive.
        #expect(store.downloadedChapter(chapterID) != nil)
        #expect(store.isComplete(chapterID) == false)
    }

    @Test func cancellingDiscardsThePartialChapterAndFreesItsSlot() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(8)
        let manager = makeManager(store: store, pages: pages)
        DownloadStubURLProtocol.setDelay(0.2)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        // Cancel once it is genuinely running, not merely queued: a request in
        // flight is what proves the chapter reached the front of the queue.
        await waitUntil { DownloadStubURLProtocol.requests.isEmpty == false }
        manager.cancel(chapterID)
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .notDownloaded)
        #expect(store.downloadedChapter(chapterID) == nil)
        for page in pages {
            #expect(store.hasPage(page, of: chapterID) == false)
        }
        #expect(store.downloadedChapters().isEmpty)
    }

    @Test func backgroundingPausesAndReturningResumesWithoutRefetching() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(6)
        let manager = makeManager(store: store, pages: pages)
        DownloadStubURLProtocol.setDelay(0.15)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        // Paused only once some pages have genuinely landed, so "resume did not
        // start over" is a claim about something.
        await waitUntil { pages.contains { store.hasPage($0, of: chapterID) } }
        manager.pause()
        await manager.waitUntilIdle()

        let stored = pages.filter { store.hasPage($0, of: chapterID) }
        #expect(stored.isEmpty == false)
        // Pausing keeps the slot and the pages; it is not a cancellation.
        #expect(store.downloadedChapter(chapterID) != nil)
        #expect(store.isComplete(chapterID) == false)

        // Everything from here is the resumed half, which is the only half this
        // test has a claim about. Counting across both halves instead made the
        // assertion depend on exactly which fetches the pause interrupted —
        // a page requested and then cancelled mid-flight is legitimately
        // requested twice, and which pages those are is a matter of timing.
        DownloadStubURLProtocol.clearRequests()
        DownloadStubURLProtocol.setDelay(0)
        manager.resume()
        await manager.waitUntilIdle()

        #expect(manager.state(for: chapterID) == .downloaded)
        for page in stored {
            // Not re-fetched: resume is page-level, so what is already on disk
            // costs nothing.
            #expect(DownloadStubURLProtocol.requestCount(for: page) == 0)
        }
        // And it genuinely finished the job rather than finding nothing to do.
        #expect(DownloadStubURLProtocol.requests.isEmpty == false)
    }

    // MARK: - The cap

    @Test func aDownloadBeyondTheCapEvictsTheOldestAndProceeds() async throws {
        let (store, root) = try makeStore(chapterLimit: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(3)

        let oldest = DownloadedChapter(
            comicID: "comic-1",
            comicTitle: "Alpha",
            chapterID: "already-here",
            chapterNumber: 9,
            chapterTitle: "Nine",
            pageURLs: [URL(string: "https://example.test/old-page.jpg")!],
            pageCount: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            isComplete: true
        )
        try store.admit(oldest)
        try store.writePage(Data("old bytes".utf8), for: oldest.pageURLs[0], of: oldest.id)

        // Built after the store is populated, the way a launch on a device that
        // already holds downloads goes.
        let manager = makeManager(store: store, pages: pages)
        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        // The reader asked for a chapter and got one, rather than being stopped
        // and asked to tidy up.
        #expect(manager.state(for: chapterID) == .downloaded)
        #expect(store.downloadedChapters().map(\.chapterID) == ["chapter-1"])
        // And the row for what went away stops claiming to be downloaded.
        #expect(manager.state(for: oldest.id) == .notDownloaded)
        #expect(store.hasPage(oldest.pageURLs[0], of: oldest.id) == false)
    }

    @Test func theChapterOpenInTheReaderIsNotTheOneEvicted() async throws {
        let (store, root) = try makeStore(chapterLimit: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(2)

        let beingRead = DownloadedChapter(
            comicID: "comic-1",
            comicTitle: "Alpha",
            chapterID: "being-read",
            chapterNumber: 8,
            chapterTitle: "Eight",
            pageCount: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            isComplete: true
        )
        let other = DownloadedChapter(
            comicID: "comic-1",
            comicTitle: "Alpha",
            chapterID: "other",
            chapterNumber: 9,
            chapterTitle: "Nine",
            pageCount: 1,
            startedAt: Date(timeIntervalSince1970: 200),
            isComplete: true
        )
        try store.admit(beingRead)
        try store.admit(other)
        let manager = makeManager(store: store, pages: pages)

        // The Reader announces what it is holding open; without that, the oldest
        // of these two is exactly what the cap would take.
        manager.readerOpened(comicID: "comic-1", chapterID: "being-read")
        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))
        await manager.waitUntilIdle()

        #expect(store.downloadedChapter(beingRead.id) != nil)
        #expect(store.downloadedChapter(other.id) == nil)
        #expect(manager.state(for: beingRead.id) == .downloaded)
        // And the row for what did go stops claiming to be downloaded.
        #expect(manager.state(for: other.id) == .notDownloaded)
    }

    @Test func theSlotsInUseAreReportedFromTheMomentADownloadStarts() async throws {
        let (store, root) = try makeStore(chapterLimit: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = pageURLs(6)
        let manager = makeManager(store: store, pages: pages)
        DownloadStubURLProtocol.setDelay(0.2)

        #expect(manager.usedSlots == 0)

        manager.download(comic: Self.comic, chapter: summary(pageCount: pages.count))

        // Counted before a single page has arrived — which is what stops a queue
        // of downloads sailing past the cap while they are all still in flight.
        #expect(manager.usedSlots == 1)

        await waitUntil { DownloadStubURLProtocol.requests.isEmpty == false }
        manager.cancel(chapterID)
        await manager.waitUntilIdle()

        #expect(manager.usedSlots == 0)
    }
}
