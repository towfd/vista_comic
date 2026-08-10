//
//  PageImageCacheTests.swift
//  vista_comicTests
//
//  Coverage for `reader-page-prefetch` tickets 01 and 02: the image cache that
//  makes a Page already in memory appear with no second download and no
//  placeholder frame, and the sliding window that puts it there before the
//  reader arrives.
//
//  These assert on what the outside world observes — which URLs were
//  requested, how many times, what the cache hands back — never on how
//  retention is implemented internally. No test here asserts that a particular
//  container holds a particular key, so the store can be replaced without
//  rewriting the suite.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it records *every*
/// request it sees and serves a per-URL body, optionally after a delay so a
/// fetch can be observed while still in flight.
///
/// File-private and not shared with `AuthorizedAsyncImageTests` or
/// `APIComicRepositoryTests` on purpose — see the comment on those files'
/// identically-shaped stubs for why: a shared stub's static state raced across
/// suites, since Swift Testing may run different `@Suite`s in parallel with
/// each other even though `.serialized` only keeps tests *within* one suite
/// sequential.
///
/// Its statics are lock-guarded rather than plain `var`s, because unlike those
/// stubs this one is written from several concurrent loading threads at once —
/// that concurrency is the point of the coalescing tests.
private final class CacheStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recordedRequests: [URLRequest] = []
    private static var bodies: [URL: Data] = [:]
    private static var status = 200
    private static var delay: TimeInterval = 0
    private static var perURLDelays: [URL: TimeInterval] = [:]
    /// Requests torn down by `stopLoading` — i.e. genuinely cancelled at the
    /// transport, not merely asked to stop somewhere upstream. This is what
    /// makes a cancellation test mean something.
    private static var cancelledURLs: [URL] = []
    private static var loadsInProgress = 0
    private static var peakLoadsInProgress = 0

    /// Clears every recorded request and canned response. Called at the start
    /// of each test so counts start from zero.
    static func reset() {
        lock.withLock {
            recordedRequests = []
            bodies = [:]
            status = 200
            delay = 0
            perURLDelays = [:]
            cancelledURLs = []
            loadsInProgress = 0
            peakLoadsInProgress = 0
        }
    }

    static func serve(_ body: Data, for url: URL) {
        lock.withLock { bodies[url] = body }
    }

    static func setStatus(_ code: Int) {
        lock.withLock { status = code }
    }

    /// Holds every response back by `seconds`, so a second ask for the same
    /// URL arrives while the first fetch is genuinely still running.
    static func setDelay(_ seconds: TimeInterval) {
        lock.withLock { delay = seconds }
    }

    /// Holds one URL's response back independently of the rest, so a test can
    /// make some fetches slow and others instant — which is how "the slow ones
    /// were cancelled and gave their slots back" becomes observable rather
    /// than a matter of timing luck.
    static func setDelay(_ seconds: TimeInterval, for url: URL) {
        lock.withLock { perURLDelays[url] = seconds }
    }

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func requestCount(for url: URL) -> Int {
        lock.withLock { recordedRequests.filter { $0.url == url }.count }
    }

    static var cancelled: [URL] {
        lock.withLock { cancelledURLs }
    }

    /// The most requests that were ever loading at the same moment.
    static var peakConcurrentLoads: Int {
        lock.withLock { peakLoadsInProgress }
    }

    /// Guards against a delayed response landing after the request was
    /// cancelled — and against counting the same load as finished twice.
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
        let url = request.url!
        let (body, statusCode, delay) = CacheStubURLProtocol.lock.withLock {
            CacheStubURLProtocol.recordedRequests.append(request)
            CacheStubURLProtocol.loadsInProgress += 1
            CacheStubURLProtocol.peakLoadsInProgress = max(
                CacheStubURLProtocol.peakLoadsInProgress,
                CacheStubURLProtocol.loadsInProgress
            )
            return (
                CacheStubURLProtocol.bodies[url] ?? Data(),
                CacheStubURLProtocol.status,
                CacheStubURLProtocol.perURLDelays[url] ?? CacheStubURLProtocol.delay
            )
        }

        let respond = { [weak self] in
            guard let self, self.settleOnce() else { return }
            CacheStubURLProtocol.lock.withLock { CacheStubURLProtocol.loadsInProgress -= 1 }
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
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
        let url = request.url!
        CacheStubURLProtocol.lock.withLock {
            CacheStubURLProtocol.loadsInProgress -= 1
            CacheStubURLProtocol.cancelledURLs.append(url)
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CacheStubURLProtocol.self]
        // Well above the cache's own limit of four, so a concurrency assertion
        // is measuring the cache rather than `URLSession`'s connection pool.
        configuration.httpMaximumConnectionsPerHost = 32
        return URLSession(configuration: configuration)
    }
}

/// A substitute cache, standing in for the real one through the environment.
private struct StubPageImageCache: PageImageCache {
    let stubbedImage: UIImage

    func cachedImage(for url: URL) -> UIImage? { stubbedImage }

    func image(for url: URL) async throws -> UIImage { stubbedImage }

    func setPrefetchWindow(pageURLs: [URL], currentIndex: Int) {}

    func heightRatio(for url: URL) -> CGFloat? { nil }
}

@Suite("PageImageCache", .serialized)
struct PageImageCacheTests {
    private static let pageURL = URL(string: "https://api.example.com/media/comic/chapter/1")!
    private static let otherPageURL = URL(string: "https://api.example.com/media/comic/chapter/2")!

    private func makeCache(
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> MemoryPageImageCache {
        MemoryPageImageCache(
            session: CacheStubURLProtocol.makeSession(),
            clientID: clientID,
            clientSecret: clientSecret
        )
    }

    /// A solid-colour PNG of an exact pixel size, so tests can tell one
    /// served body from another and check that nothing was downsampled.
    private static func makePNG(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }

    // MARK: - The synchronous hit path

    /// The assertion that protects the no-flash guarantee. If this is lost,
    /// the old "placeholder frame first" behaviour comes back silently with
    /// everything else still passing.
    @Test func residentImageIsReadableSynchronously() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        let cache = makeCache()

        _ = try await cache.image(for: Self.pageURL)

        // No `await`: exactly what a SwiftUI body can do.
        let resident = try #require(cache.cachedImage(for: Self.pageURL))
        #expect(resident.size == CGSize(width: 8, height: 12))
    }

    @Test func synchronousLookupReturnsNothingForAnAbsentURLAndFetchesNothing() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        let cache = makeCache()

        #expect(cache.cachedImage(for: Self.pageURL) == nil)

        // Give any (incorrectly) started request a chance to be recorded.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(CacheStubURLProtocol.requests.isEmpty)
    }

    // MARK: - One request per image

    @Test func askingTwiceInSequenceIssuesOneNetworkRequest() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        let cache = makeCache()

        _ = try await cache.image(for: Self.pageURL)
        _ = try await cache.image(for: Self.pageURL)

        #expect(CacheStubURLProtocol.requestCount(for: Self.pageURL) == 1)
    }

    @Test func twoConcurrentAsksIssueOneNetworkRequest() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        // Hold the response open so the second ask genuinely arrives while the
        // first fetch is still running, rather than after it stored its image.
        CacheStubURLProtocol.setDelay(0.2)
        let cache = makeCache()

        async let first = cache.image(for: Self.pageURL)
        async let second = cache.image(for: Self.pageURL)
        let (one, two) = try await (first, second)

        #expect(CacheStubURLProtocol.requestCount(for: Self.pageURL) == 1)
        // Both callers got the same decoded image, not one real and one empty.
        #expect(one.size == two.size)
    }

    @Test func differentURLsAreCachedSeparately() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        CacheStubURLProtocol.serve(Self.makePNG(width: 30, height: 40), for: Self.otherPageURL)
        let cache = makeCache()

        _ = try await cache.image(for: Self.pageURL)
        _ = try await cache.image(for: Self.otherPageURL)

        #expect(cache.cachedImage(for: Self.pageURL)?.size == CGSize(width: 8, height: 12))
        #expect(cache.cachedImage(for: Self.otherPageURL)?.size == CGSize(width: 30, height: 40))
    }

    // MARK: - Resolution

    /// Crops for recognition are taken from these pixels, so a cached image
    /// must carry every one of them — downsampling here would silently degrade
    /// recognition quality.
    @Test func cachesAtFullSourceResolution() async throws {
        CacheStubURLProtocol.reset()
        let body = Self.makePNG(width: 120, height: 340)
        CacheStubURLProtocol.serve(body, for: Self.pageURL)
        let cache = makeCache()

        let loaded = try await cache.image(for: Self.pageURL)

        let source = try #require(UIImage(data: body))
        #expect(loaded.size == source.size)
        let sourcePixels = try #require(source.cgImage)
        let loadedPixels = try #require(loaded.cgImage)
        #expect(loadedPixels.width == sourcePixels.width)
        #expect(loadedPixels.height == sourcePixels.height)
    }

    /// A cached image must have nothing left to decode when it is drawn, since
    /// it is drawn mid-scroll. The observable form of that: it is backed by a
    /// raw bitmap rather than by a reader over the response bytes — an image
    /// still holding its source's `utType` is one whose pixels have not been
    /// produced yet.
    ///
    /// This is deterministic only because the cache builds that bitmap itself.
    /// The first attempt used `UIImage.preparingForDisplay()`, and this exact
    /// assertion caught it handing back a still-encoded image under load while
    /// passing when run alone — which is why the check earns its place.
    @Test func aCachedImageHasAlreadyBeenDecoded() async throws {
        CacheStubURLProtocol.reset()
        let body = Self.makePNG(width: 120, height: 340)
        CacheStubURLProtocol.serve(body, for: Self.pageURL)
        let cache = makeCache()

        let loaded = try await cache.image(for: Self.pageURL)

        // The undecoded baseline, for contrast: this is what the cache would
        // have stored had it simply kept what `UIImage(data:)` produced.
        let undecoded = try #require(UIImage(data: body))
        #expect(undecoded.cgImage?.utType != nil)
        #expect(loaded.cgImage?.utType == nil)
    }

    // MARK: - Cloudflare Access

    /// Asserted at the cache level as well as the view level, so moving the
    /// fetch behind the cache can't quietly lose the headers that
    /// `AuthorizedAsyncImageTests` was written to protect.
    @Test func requestsCarryCloudflareAccessHeaders() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        let cache = makeCache(clientID: "test-client-id", clientSecret: "test-client-secret")

        _ = try await cache.image(for: Self.pageURL)

        let request = try #require(CacheStubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func requestsOmitCloudflareAccessHeadersWhenUnconfigured() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        let cache = makeCache()

        _ = try await cache.image(for: Self.pageURL)

        let request = try #require(CacheStubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    // MARK: - Failure

    /// The Reader's tappable failure placeholder re-requests through the
    /// cache, so a failure must leave nothing behind that would replay itself
    /// instead of trying the network again.
    @Test func aFailedFetchIsNotCachedAndARetryRequestsAgain() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Data("<html>blocked</html>".utf8), for: Self.pageURL)
        CacheStubURLProtocol.setStatus(403)
        let cache = makeCache()

        await #expect(throws: (any Error).self) {
            _ = try await cache.image(for: Self.pageURL)
        }
        #expect(cache.cachedImage(for: Self.pageURL) == nil)

        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        CacheStubURLProtocol.setStatus(200)
        _ = try await cache.image(for: Self.pageURL)

        #expect(CacheStubURLProtocol.requestCount(for: Self.pageURL) == 2)
        #expect(cache.cachedImage(for: Self.pageURL) != nil)
    }

    // MARK: - Retention

    /// Retention is bounded by decoded *bytes*, not by a count of images —
    /// Page heights in this library vary 64-fold, so a count would mean wildly
    /// different memory for the same number of Pages.
    ///
    /// Asserts only that the budget is enforced and that the cache still holds
    /// something, never *which* entries survived: the store's eviction order
    /// is documented as unspecified, so an order-dependent assertion here
    /// would be a flake waiting to happen.
    @Test func retentionIsBoundedByTotalDecodedBytes() async throws {
        CacheStubURLProtocol.reset()
        let urls = (0..<8).map {
            URL(string: "https://api.example.com/media/comic/chapter/budget/\($0)")!
        }
        for url in urls {
            CacheStubURLProtocol.serve(Self.makePNG(width: 200, height: 200), for: url)
        }

        // Measure what one of these actually costs once decoded, rather than
        // assuming width × height × 4: the bitmap's row stride is padded for
        // alignment, so the real cost is a little higher.
        let unbounded = makeCache()
        let costPerImage = Self.decodedByteCount(of: try await unbounded.image(for: urls[0]))
        #expect(costPerImage > 0)

        let budget = costPerImage * 3
        let cache = MemoryPageImageCache(
            session: CacheStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            byteLimit: budget
        )
        for url in urls {
            _ = try await cache.image(for: url)
        }

        let residentBytes = urls
            .compactMap { cache.cachedImage(for: $0) }
            .reduce(0) { $0 + Self.decodedByteCount(of: $1) }
        #expect(residentBytes <= budget)
        // Not vacuous: a cache that retained nothing at all would also stay
        // under budget, and would defeat the entire feature.
        #expect(residentBytes > 0)
    }

    /// Mirrors how the cache itself sizes an entry, so the budget assertion is
    /// expressed in the same units the budget is set in.
    private static func decodedByteCount(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    @Test func everythingIsReleasedOnAMemoryWarning() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 8, height: 12), for: Self.pageURL)
        CacheStubURLProtocol.serve(Self.makePNG(width: 30, height: 40), for: Self.otherPageURL)
        let cache = makeCache()

        _ = try await cache.image(for: Self.pageURL)
        _ = try await cache.image(for: Self.otherPageURL)
        #expect(cache.cachedImage(for: Self.pageURL) != nil)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        #expect(cache.cachedImage(for: Self.pageURL) == nil)
        #expect(cache.cachedImage(for: Self.otherPageURL) == nil)
    }

    // MARK: - Reserved proportions (ticket 03)
    //
    // A Page's proportions are held here rather than by the row that draws it
    // precisely so they outlive the two things that destroy a row's state: the
    // reader's `LazyVStack` recycling it, and this cache evicting the image.
    // The assertions below are therefore all of the form "the image went, the
    // proportions stayed" — the property the reader depends on to stop its
    // content collapsing.

    @Test func decodingAPageRecordsItsProportions() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 900, height: 1800), for: Self.pageURL)
        let cache = makeCache()

        #expect(cache.heightRatio(for: Self.pageURL) == nil)
        _ = try await cache.image(for: Self.pageURL)

        #expect(cache.heightRatio(for: Self.pageURL) == 2.0)
    }

    @Test func proportionsOutliveEviction() async throws {
        CacheStubURLProtocol.reset()
        let urls = (0..<8).map {
            URL(string: "https://api.example.com/media/comic/chapter/ratio/\($0)")!
        }
        for url in urls {
            CacheStubURLProtocol.serve(Self.makePNG(width: 100, height: 200), for: url)
        }

        let unbounded = makeCache()
        let costPerImage = Self.decodedByteCount(of: try await unbounded.image(for: urls[0]))
        let cache = MemoryPageImageCache(
            session: CacheStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil,
            byteLimit: costPerImage * 2
        )
        for url in urls {
            _ = try await cache.image(for: url)
        }

        // Not vacuous: with a budget of two images, most of these are gone.
        let evicted = urls.filter { cache.cachedImage(for: $0) == nil }
        #expect(!evicted.isEmpty)

        // Every one of them still reserves its correct height.
        for url in evicted {
            #expect(cache.heightRatio(for: url) == 2.0)
        }
    }

    @Test func proportionsSurviveAMemoryWarning() async throws {
        CacheStubURLProtocol.reset()
        CacheStubURLProtocol.serve(Self.makePNG(width: 900, height: 1350), for: Self.pageURL)
        let cache = makeCache()
        _ = try await cache.image(for: Self.pageURL)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // The purge is when every row rebuilds from nothing at once, so it is
        // the moment stable heights matter most — dropping the proportions
        // here would reintroduce the collapse at its worst.
        #expect(cache.cachedImage(for: Self.pageURL) == nil)
        #expect(cache.heightRatio(for: Self.pageURL) == 1.5)
    }

    @Test func aPageNeverHeldHasNoProportions() {
        #expect(makeCache().heightRatio(for: Self.otherPageURL) == nil)
    }

    // MARK: - The prefetch window

    private static func chapterURLs(_ count: Int, chapter: String = "window") -> [URL] {
        (0..<count).map {
            URL(string: "https://api.example.com/media/comic/\(chapter)/\($0)")!
        }
    }

    /// Small bodies on purpose: these tests are about which URLs are asked for
    /// and when, and a 20×30 page keeps decode cost out of the timings.
    private func serve(_ urls: [URL]) {
        let body = Self.makePNG(width: 20, height: 30)
        for url in urls {
            CacheStubURLProtocol.serve(body, for: url)
        }
    }

    /// Polls for an outcome rather than sleeping a fixed time. The window is
    /// fire-and-forget by design — it returns before any work is done — so a
    /// test has to wait for a result, not for a duration.
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    private func areResident(_ urls: some Collection<URL>, in cache: MemoryPageImageCache) -> Bool {
        urls.allSatisfy { cache.cachedImage(for: $0) != nil }
    }

    /// The window's shape, and the fact that it is seeded where the reader
    /// actually is: a window opened at page 11 must not fetch page 1.
    @Test func aWindowRequestsTheCurrentPageFiveAheadAndTwoBehindAndNothingElse() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(30)
        serve(urls)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 10)

        let expected = Set(urls[8...15])
        let arrived = await waitUntil { self.areResident(expected, in: cache) }
        #expect(arrived)
        #expect(Set(CacheStubURLProtocol.requests.compactMap(\.url)) == expected)
        #expect(CacheStubURLProtocol.requests.count == 8)
    }

    @Test func aWindowNearTheEndOfAChapterClampsInsteadOfRequestingPastTheLastPage() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(12)
        serve(urls)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 11)

        let expected = Set(urls[9...11])
        let arrived = await waitUntil { self.areResident(expected, in: cache) }
        #expect(arrived)
        #expect(Set(CacheStubURLProtocol.requests.compactMap(\.url)) == expected)
        #expect(CacheStubURLProtocol.requests.count == 3)
    }

    @Test func anEmptyChapterRequestsNothing() async throws {
        CacheStubURLProtocol.reset()
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: [], currentIndex: 0)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(CacheStubURLProtocol.requests.isEmpty)
    }

    /// Scrolling must cost only the pages newly come into range — otherwise the
    /// window would re-download most of itself on every slide.
    @Test func slidingTheWindowForwardOnlyRequestsNewlyEnteredPages() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(20)
        serve(urls)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 0)
        #expect(await waitUntil { self.areResident(urls[0...5], in: cache) })

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 3)
        #expect(await waitUntil { self.areResident(urls[0...8], in: cache) })

        for index in 0...8 {
            #expect(CacheStubURLProtocol.requestCount(for: urls[index]) == 1)
        }
        #expect(CacheStubURLProtocol.requests.count == 9)
    }

    /// Four at a time hides round-trip latency without saturating the
    /// connection or the decoder. The window is eight pages wide, so half of it
    /// must be made to wait.
    @Test func noMoreThanFourFetchesRunAtOnce() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(30)
        serve(urls)
        // Long enough that fetches genuinely overlap; without a delay each
        // would finish before the next began and the cap would be untested.
        CacheStubURLProtocol.setDelay(0.2)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 10)

        #expect(await waitUntil { self.areResident(urls[8...15], in: cache) })
        #expect(CacheStubURLProtocol.peakConcurrentLoads == 4)
    }

    /// The anti-stall guarantee. Asserted two ways, because "we called cancel"
    /// on its own would prove nothing: the abandoned requests are torn down at
    /// the transport, *and* the pages the reader actually landed on arrive far
    /// sooner than the abandoned ones could possibly have finished.
    @Test func pagesLeavingTheWindowAreCancelledAndGiveTheirSlotsBack() async throws {
        CacheStubURLProtocol.reset()
        let abandoned = Self.chapterURLs(6, chapter: "abandoned")
        let landed = Self.chapterURLs(6, chapter: "landed")
        serve(abandoned)
        serve(landed)
        // Left to finish, these four would hold every slot for five seconds.
        for url in abandoned {
            CacheStubURLProtocol.setDelay(5, for: url)
        }
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: abandoned, currentIndex: 0)
        #expect(await waitUntil { CacheStubURLProtocol.requests.count >= 4 })

        // A fast scroll onward: nothing in the old window is wanted any more.
        cache.setPrefetchWindow(pageURLs: landed, currentIndex: 0)

        let arrived = await waitUntil(timeout: 3) { self.areResident(landed, in: cache) }
        #expect(arrived)
        #expect(Set(CacheStubURLProtocol.cancelled) == Set(abandoned.prefix(4)))
        #expect(abandoned.allSatisfy { cache.cachedImage(for: $0) == nil })
        // The two that never got a slot left without ever hitting the network.
        #expect(CacheStubURLProtocol.requestCount(for: abandoned[4]) == 0)
        #expect(CacheStubURLProtocol.requestCount(for: abandoned[5]) == 0)
    }

    /// A page the reader has actually reached must not sit behind prefetches
    /// for pages further down that were queued before it.
    @Test func aPageTheReaderLandsOnIsFetchedAheadOfQueuedPrefetches() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(10, chapter: "priority")
        serve(urls)
        // Long enough that the explicit ask below lands while the first four
        // still hold every slot.
        CacheStubURLProtocol.setDelay(0.4)
        let cache = makeCache()

        // Pages 1–6 wanted; pages 1–4 start, pages 5 and 6 queue behind them.
        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 0)
        #expect(await waitUntil { CacheStubURLProtocol.requests.count >= 4 })

        // The reader lands on page 6 — the very last thing the window queued.
        _ = try await cache.image(for: urls[5])

        let order = CacheStubURLProtocol.requests.compactMap(\.url)
        #expect(order.count >= 5)
        // The first freed slot went to it, ahead of page 5 which queued first.
        #expect(order[4] == urls[5])
    }

    /// The anti-storm guarantee. Without the failure mark the reconciler would
    /// see "not resident, not in flight", re-request, fail, and loop — a dead
    /// network would become a request storm.
    @Test func aFailedURLIsNotReRequestedByASubsequentWindowReconcile() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(10, chapter: "dead")
        serve(urls)
        CacheStubURLProtocol.setStatus(503)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 0)
        #expect(await waitUntil { CacheStubURLProtocol.requests.count == 6 })
        // Give a storm every chance to show itself.
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(CacheStubURLProtocol.requests.count == 6)

        // Re-centring over the same dead pages asks for the one page that has
        // not been tried yet, and for none of the six that already failed.
        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 1)
        #expect(await waitUntil { CacheStubURLProtocol.requests.count == 7 })
        try await Task.sleep(nanoseconds: 250_000_000)

        for index in 0...6 {
            #expect(CacheStubURLProtocol.requestCount(for: urls[index]) == 1)
        }
        #expect(CacheStubURLProtocol.requests.count == 7)
    }

    /// The other half of the mark: it must never make a page permanently
    /// unloadable. This is the path the Reader's tappable failure placeholder
    /// takes, and the path taken when the reader simply scrolls to the page.
    @Test func anExplicitRequestReRequestsAPageThePrefetchWindowGaveUpOn() async throws {
        CacheStubURLProtocol.reset()
        let urls = Self.chapterURLs(10, chapter: "recovered")
        serve(urls)
        CacheStubURLProtocol.setStatus(503)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 0)
        #expect(await waitUntil { CacheStubURLProtocol.requests.count == 6 })

        CacheStubURLProtocol.setStatus(200)
        _ = try await cache.image(for: urls[0])

        #expect(CacheStubURLProtocol.requestCount(for: urls[0]) == 2)
        #expect(cache.cachedImage(for: urls[0]) != nil)

        // Marks are per URL, and the reconciler still leaves the other five
        // alone: recovering one page does not restart the storm for the rest.
        cache.setPrefetchWindow(pageURLs: urls, currentIndex: 0)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(CacheStubURLProtocol.requestCount(for: urls[0]) == 2)
        #expect(CacheStubURLProtocol.requests.count == 7)
    }

    /// Chapter changes re-seed the window; they never clear the cache. This is
    /// what makes flipping to the previous or next chapter and back instant.
    @Test func aNewChaptersWindowKeepsWhatThePreviousOneCached() async throws {
        CacheStubURLProtocol.reset()
        let previous = Self.chapterURLs(6, chapter: "previous")
        let next = Self.chapterURLs(6, chapter: "next")
        serve(previous)
        serve(next)
        let cache = makeCache()

        cache.setPrefetchWindow(pageURLs: previous, currentIndex: 0)
        #expect(await waitUntil { self.areResident(previous, in: cache) })

        cache.setPrefetchWindow(pageURLs: next, currentIndex: 0)
        #expect(await waitUntil { self.areResident(next, in: cache) })

        #expect(self.areResident(previous, in: cache))

        // Flipping back re-seeds without a single new request.
        cache.setPrefetchWindow(pageURLs: previous, currentIndex: 0)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(CacheStubURLProtocol.requests.count == 12)
    }

    // MARK: - Substitution

    /// Previews and reader-level tests swap the cache the same way the Reader
    /// already swaps its repository, recognizer and translator.
    @MainActor
    @Test func theCacheIsSubstitutableThroughTheEnvironment() {
        var values = EnvironmentValues()
        #expect(values.pageImageCache is MemoryPageImageCache)

        values.pageImageCache = StubPageImageCache(stubbedImage: UIImage())
        #expect(values.pageImageCache is StubPageImageCache)
    }
}
