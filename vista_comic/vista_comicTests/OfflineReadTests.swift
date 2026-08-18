//
//  OfflineReadTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 02: reading what is on the device
//  when the network cannot answer, and — just as important — *not* pretending
//  to when the server is there and something is genuinely wrong.
//
//  The fallbacks are driven by injecting a **failing inner repository** rather
//  than by stubbing the network, because the failure is what is under test and
//  injecting it one level up says so directly. The disk-first image path is the
//  exception: the claim there is "no request was issued", which only a stubbed
//  `URLProtocol` can witness.
//

import Foundation
import Testing
import UIKit
@testable import vista_comic

/// An inner `ComicRepository` that fails on demand. One error for all three
/// reads, since no test needs them to disagree.
private struct InnerRepositoryDouble: ComicRepository {
    var error: (any Error)?
    var comics: [Comic] = []
    var comicDetail = Comic(id: "comic-1", title: "Alpha", coverURL: nil)
    var chapter = Chapter(id: "chapter-1", number: 1, title: "One")

    func library() async throws -> [Comic] {
        if let error { throw error }
        return comics
    }

    func comic(id: String) async throws -> Comic {
        if let error { throw error }
        return comicDetail
    }

    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        if let error { throw error }
        return chapter
    }

    func rescan() async throws {
        if let error { throw error }
    }

    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        if let error { throw error }
    }
}

/// A stub `URLProtocol` for the two claims that are about requests rather than
/// about results. File-private for the reason the other suites give: static
/// state raced when it was shared between suites.
private final class OfflineReadStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var body = Data()
    private static var recordedRequests: [URLRequest] = []

    static func reset(serving body: Data) {
        lock.withLock {
            self.body = body
            recordedRequests = []
        }
    }

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineReadStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.lock.withLock { () -> Data in
            Self.recordedRequests.append(request)
            return Self.body
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Offline reading", .serialized)
struct OfflineReadTests {

    // MARK: - Fixtures

    private static let libraryJSON = Data("""
    [
      {"id": "comic-1", "title": "Alpha", "coverUrl": "https://example.test/cover-1", "chapterCount": 2}
    ]
    """.utf8)

    private static let comicJSON = Data("""
    {
      "id": "comic-1",
      "title": "Alpha",
      "coverUrl": "https://example.test/cover-1",
      "chapters": [
        {"id": "chapter-1", "number": 1, "title": "One", "pageCount": 3, "readState": "unread"}
      ]
    }
    """.utf8)

    private static let chapterID = DownloadedChapterID(comicID: "comic-1", chapterID: "chapter-1")

    private static let pages = [
        URL(string: "https://example.test/media/comic-1/chapter-1/page-1.jpg")!,
        URL(string: "https://example.test/media/comic-1/chapter-1/page-2.jpg")!,
    ]

    /// The network being unreachable, as `URLSession` reports it.
    private static let offline = URLError(.notConnectedToInternet)

    private func makeSnapshots(library: Data? = nil, comic: Data? = nil) -> InMemoryCatalogSnapshotStore {
        let snapshots = InMemoryCatalogSnapshotStore()
        if let library { snapshots.store(library, for: .library) }
        if let comic { snapshots.store(comic, for: .comic(id: "comic-1")) }
        return snapshots
    }

    /// A store holding one downloaded chapter, complete or not.
    private func makeChapterStore(complete: Bool) throws -> InMemoryOfflineChapterStore {
        let store = InMemoryOfflineChapterStore()
        try store.admit(
            DownloadedChapter(
                comicID: "comic-1",
                comicTitle: "Alpha",
                chapterID: "chapter-1",
                chapterNumber: 1,
                chapterTitle: "One",
                pageURLs: Self.pages,
                pageCount: Self.pages.count,
                isComplete: complete
            )
        )
        return store
    }

    /// A solid-colour PNG, so the image path has something a `UIImage` will
    /// genuinely decode.
    private static func makePNG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 8, height: 12)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    // MARK: - The catalog, with no connection

    @Test func theLibraryRendersFromTheLastSuccessfulResponseWhenOffline() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: makeSnapshots(library: Self.libraryJSON),
            chapters: InMemoryOfflineChapterStore()
        )

        let comics = try await repository.library()

        #expect(comics.map(\.id) == ["comic-1"])
        // The chapter *count* is what the library card shows, and it comes from
        // the stored bytes rather than from anything the device recomputed.
        #expect(comics.first?.chapterCount == 2)
    }

    @Test func aComicsChapterListRendersFromTheLastSuccessfulResponseWhenOffline() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: makeSnapshots(comic: Self.comicJSON),
            chapters: InMemoryOfflineChapterStore()
        )

        let comic = try await repository.comic(id: "comic-1")

        #expect(comic.chapters.map(\.id) == ["chapter-1"])
    }

    @Test func aServerErrorIsNotMaskedByTheStoredCatalog() async throws {
        // The server answered, and it answered badly. Serving yesterday's
        // library instead would look perfectly fine on screen and be silently
        // out of date, with nothing to tell the reader either way.
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: APIError.httpStatus(500)),
            snapshots: makeSnapshots(library: Self.libraryJSON),
            chapters: InMemoryOfflineChapterStore()
        )

        await #expect(throws: APIError.self) {
            _ = try await repository.library()
        }
    }

    @Test func beingOfflineWithNothingStoredStillFails() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: InMemoryOfflineChapterStore()
        )

        await #expect(throws: URLError.self) {
            _ = try await repository.library()
        }
    }

    @Test func aSuccessfulResponseIsWhatRefreshesWhatIsStored() async throws {
        // The only claim here that needs a real request: bytes are stored by the
        // repository that actually receives them, since a decorator is handed
        // decoded models and could never write them back.
        OfflineReadStubURLProtocol.reset(serving: Self.libraryJSON)
        let snapshots = InMemoryCatalogSnapshotStore()
        let api = APIComicRepository(
            baseURL: URL(string: "https://api.example.test")!,
            session: OfflineReadStubURLProtocol.makeSession(),
            cfAccessClientID: nil,
            cfAccessClientSecret: nil,
            snapshots: snapshots
        )

        _ = try await api.library()

        #expect(snapshots.data(for: .library) == Self.libraryJSON)
        // And the reader endpoint is deliberately not stored: a downloaded
        // chapter's record answers that request, and a stored response would
        // answer it for chapters whose pages are not on the device.
        _ = try? await api.readerChapter(comicID: "comic-1", chapterID: "chapter-1")
        #expect(snapshots.data(for: .comic(id: "comic-1")) == nil)
    }

    // MARK: - The reader, with no connection

    @Test func aDownloadedChapterOpensFromItsRecordWhenOffline() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: try makeChapterStore(complete: true)
        )

        let chapter = try await repository.readerChapter(comicID: "comic-1", chapterID: "chapter-1")

        // The ordered page URLs are the whole reason the record exists.
        #expect(chapter.pageURLs == Self.pages)
        #expect(chapter.title == "One")
    }

    @Test func aChapterThatWasNeverDownloadedSaysSoRatherThanFailing() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: InMemoryOfflineChapterStore()
        )

        await #expect(throws: OfflineReadError.chapterNotAvailableOffline) {
            _ = try await repository.readerChapter(comicID: "comic-1", chapterID: "chapter-1")
        }
    }

    @Test func aPartlyDownloadedChapterIsNotAvailableOffline() async throws {
        // It would open, read beautifully, and stop — at the moment there is no
        // connection to fix it with.
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: Self.offline),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: try makeChapterStore(complete: false)
        )

        await #expect(throws: OfflineReadError.chapterNotAvailableOffline) {
            _ = try await repository.readerChapter(comicID: "comic-1", chapterID: "chapter-1")
        }
    }

    @Test func aServerErrorSurfacesEvenForAChapterThatIsDownloaded() async throws {
        let repository = OfflineFallbackComicRepository(
            wrapping: InnerRepositoryDouble(error: APIError.httpStatus(500)),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: try makeChapterStore(complete: true)
        )

        await #expect(throws: APIError.self) {
            _ = try await repository.readerChapter(comicID: "comic-1", chapterID: "chapter-1")
        }
    }

    // MARK: - The image path

    @Test func aDownloadedPageIsServedFromDiskWithNoRequest() async throws {
        let chapters = try makeChapterStore(complete: true)
        let png = Self.makePNG()
        try chapters.writePage(png, for: Self.pages[0], of: Self.chapterID)
        OfflineReadStubURLProtocol.reset(serving: png)

        let cache = MemoryPageImageCache(
            session: OfflineReadStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            offlineChapters: chapters
        )

        let image = try await cache.image(for: Self.pages[0])

        #expect(image.size == CGSize(width: 8, height: 12))
        // The point of the whole ticket, and it holds while online too.
        #expect(OfflineReadStubURLProtocol.requests.isEmpty)
    }

    @Test func aPageThatWasNotDownloadedStillGoesToTheNetwork() async throws {
        let chapters = try makeChapterStore(complete: true)
        let png = Self.makePNG()
        // Only the first page is on the device.
        try chapters.writePage(png, for: Self.pages[0], of: Self.chapterID)
        OfflineReadStubURLProtocol.reset(serving: png)

        let cache = MemoryPageImageCache(
            session: OfflineReadStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            offlineChapters: chapters
        )

        _ = try await cache.image(for: Self.pages[1])

        #expect(OfflineReadStubURLProtocol.requests.map(\.url) == [Self.pages[1]])
    }

    @Test func readingAPageNeverWritesItToDisk() async throws {
        let chapters = try makeChapterStore(complete: true)
        OfflineReadStubURLProtocol.reset(serving: Self.makePNG())

        let cache = MemoryPageImageCache(
            session: OfflineReadStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            offlineChapters: chapters
        )

        _ = try await cache.image(for: Self.pages[1])

        // The invariant the feature rests on: what is on the device is exactly
        // what was downloaded on purpose, so the 已下載 list, the cap and the
        // disk cannot drift apart.
        #expect(chapters.pageData(for: Self.pages[1]) == nil)
        #expect(chapters.hasPage(Self.pages[1], of: Self.chapterID) == false)
    }
}
