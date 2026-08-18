//
//  CoverCacheTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 07: a comic's cover survives to the
//  next launch, a chapter thumbnail does not, and the library is what decides
//  which is which.
//
//  The claims worth proving here are about *requests* and about *which store
//  was written*, so the network is stubbed and both stores are inspected
//  directly. Files go to a temporary directory, never the real Application
//  Support path.
//

import Foundation
import Testing
import UIKit
@testable import vista_comic

/// A stub `URLProtocol` serving one body and recording what was asked for.
/// File-private, like every other suite's, so nothing races across suites.
private final class CoverStubURLProtocol: URLProtocol {
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
        configuration.protocolClasses = [CoverStubURLProtocol.self]
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

/// An inner repository that answers with a fixed library, or fails.
private struct LibraryRepositoryDouble: ComicRepository {
    var error: (any Error)?
    var comics: [Comic] = []

    func library() async throws -> [Comic] {
        if let error { throw error }
        return comics
    }
    func comic(id: String) async throws -> Comic {
        Comic(id: id, title: "Alpha", coverURL: nil)
    }
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        Chapter(id: chapterID, number: 1, title: "One")
    }
    func rescan() async throws {}
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {}
}

@Suite("Comic covers on the device", .serialized)
struct CoverCacheTests {

    private static let coverURL = URL(string: "https://example.test/media/comic-1/cover.jpg")!
    private static let otherCoverURL = URL(string: "https://example.test/media/comic-2/cover.jpg")!
    /// A chapter's thumbnail: an image the app displays constantly and must
    /// never keep, since there is one per chapter.
    private static let thumbnailURL = URL(string: "https://example.test/media/comic-1/chapter-1/page-1.jpg")!

    private static func makePNG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 6, height: 9)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    private func withCoverCache(_ body: (FileCoverCache, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(try FileCoverCache(root: root), root)
    }

    private func makeCache(
        covers: any CoverCache,
        chapters: (any OfflineChapterStore)? = nil
    ) -> MemoryPageImageCache {
        MemoryPageImageCache(
            session: CoverStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            offlineChapters: chapters,
            covers: covers
        )
    }

    // MARK: - What is kept

    @Test func aCoverFetchedForDisplayIsStillThereForTheNextLaunch() async throws {
        let png = Self.makePNG()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let covers = try FileCoverCache(root: root)
        covers.setKnownCovers([Self.coverURL])
        CoverStubURLProtocol.reset(serving: png)

        // The library screen drawing a cover, which is the only thing that ever
        // fills this cache — nothing is requested that would not have been.
        _ = try await makeCache(covers: covers).image(for: Self.coverURL)
        #expect(CoverStubURLProtocol.requests.count == 1)

        // A relaunch: a fresh cache over the same directory, with an empty
        // memory cache behind it.
        CoverStubURLProtocol.reset(serving: png)
        let relaunched = try FileCoverCache(root: root)
        relaunched.setKnownCovers([Self.coverURL])
        let image = try await makeCache(covers: relaunched).image(for: Self.coverURL)

        #expect(image.size == CGSize(width: 6, height: 9))
        #expect(CoverStubURLProtocol.requests.isEmpty)
    }

    @Test func aChapterThumbnailIsNeverKept() async throws {
        try await withCoverCache { covers, _ in
            covers.setKnownCovers([Self.coverURL])
            CoverStubURLProtocol.reset(serving: Self.makePNG())

            // Fetched exactly as a cover is, and deliberately not kept: there is
            // one of these per chapter, and that is the difference between a
            // cache bounded by the library and one bounded by nothing.
            _ = try await self.makeCache(covers: covers).image(for: Self.thumbnailURL)

            #expect(covers.data(for: Self.thumbnailURL) == nil)
        }
    }

    @Test func coversThatLeftTheLibraryAreRemoved() async throws {
        try await withCoverCache { covers, root in
            covers.setKnownCovers([Self.coverURL, Self.otherCoverURL])
            covers.storeIfKnownCover(Data("one".utf8), for: Self.coverURL)
            covers.storeIfKnownCover(Data("two".utf8), for: Self.otherCoverURL)

            // The library no longer has the second comic.
            covers.setKnownCovers([Self.coverURL])

            #expect(covers.data(for: Self.coverURL) == Data("one".utf8))
            #expect(covers.data(for: Self.otherCoverURL) == nil)
            // The bytes are gone, not merely unreachable — the bound is the
            // library's own size, with no budget to tune.
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            #expect(files.count == 1)
        }
    }

    @Test func onlyTheCatalogDecidesWhatACoverIs() async throws {
        try await withCoverCache { covers, _ in
            // Nothing declared yet: even a URL that will be a cover tomorrow is
            // not one today, because the catalog has not said so.
            covers.storeIfKnownCover(Data("one".utf8), for: Self.coverURL)
            #expect(covers.data(for: Self.coverURL) == nil)

            covers.setKnownCovers([Self.coverURL])
            covers.storeIfKnownCover(Data("one".utf8), for: Self.coverURL)
            #expect(covers.data(for: Self.coverURL) == Data("one".utf8))
        }
    }

    // MARK: - Who declares them

    @Test func theLibraryResponseDeclaresTheCovers() async throws {
        let covers = InMemoryCoverCache()
        let repository = OfflineFallbackComicRepository(
            wrapping: LibraryRepositoryDouble(
                comics: [Comic(id: "comic-1", title: "Alpha", coverURL: Self.coverURL)]
            ),
            snapshots: InMemoryCatalogSnapshotStore(),
            chapters: InMemoryOfflineChapterStore(),
            covers: covers
        )

        _ = try await repository.library()

        covers.storeIfKnownCover(Data("one".utf8), for: Self.coverURL)
        #expect(covers.data(for: Self.coverURL) == Data("one".utf8))
    }

    @Test func aReplayedLibraryDeclaresThemToo() async throws {
        // Offline since launch: the covers scrolled past yesterday must still be
        // served rather than pruned by a library nobody managed to fetch.
        let snapshots = InMemoryCatalogSnapshotStore()
        snapshots.store(
            Data("""
            [{"id": "comic-1", "title": "Alpha", "coverUrl": "\(Self.coverURL.absoluteString)", "chapterCount": 1}]
            """.utf8),
            for: .library
        )
        let covers = InMemoryCoverCache()
        covers.setKnownCovers([Self.coverURL])
        covers.storeIfKnownCover(Data("one".utf8), for: Self.coverURL)

        let repository = OfflineFallbackComicRepository(
            wrapping: LibraryRepositoryDouble(error: URLError(.notConnectedToInternet)),
            snapshots: snapshots,
            chapters: InMemoryOfflineChapterStore(),
            covers: covers
        )

        _ = try await repository.library()

        #expect(covers.data(for: Self.coverURL) == Data("one".utf8))
    }

    // MARK: - The two stores stay apart

    @Test func keepingACoverTouchesNothingAboutDownloads() async throws {
        try await withCoverCache { covers, _ in
            covers.setKnownCovers([Self.coverURL])
            CoverStubURLProtocol.reset(serving: Self.makePNG())
            let chapters = InMemoryOfflineChapterStore()

            _ = try await self.makeCache(covers: covers, chapters: chapters).image(for: Self.coverURL)

            // A cover is not a download: it is not in the chapter store, so it
            // is not in the 已下載 list and does not occupy a slot.
            #expect(chapters.pageData(for: Self.coverURL) == nil)
            #expect(chapters.downloadedChapters().isEmpty)
        }
    }

    // MARK: - Where they live

    @Test func coversLiveUnderApplicationSupportAndAreExcludedFromBackup() async throws {
        let root = try FileCoverCache.defaultRoot()
        #expect(root.path.contains("Application Support"))
        #expect(root.path.contains("Caches") == false)

        try await withCoverCache { _, root in
            let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
    }
}
