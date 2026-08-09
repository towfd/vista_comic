//
//  PageImageCacheTests.swift
//  vista_comicTests
//
//  Coverage for `reader-page-prefetch` ticket 01: the image cache that makes a
//  Page already in memory appear with no second download and no placeholder
//  frame.
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

    /// Clears every recorded request and canned response. Called at the start
    /// of each test so counts start from zero.
    static func reset() {
        lock.withLock {
            recordedRequests = []
            bodies = [:]
            status = 200
            delay = 0
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

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func requestCount(for url: URL) -> Int {
        lock.withLock { recordedRequests.filter { $0.url == url }.count }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (body, statusCode, delay) = CacheStubURLProtocol.lock.withLock {
            CacheStubURLProtocol.recordedRequests.append(request)
            return (
                CacheStubURLProtocol.bodies[url] ?? Data(),
                CacheStubURLProtocol.status,
                CacheStubURLProtocol.delay
            )
        }

        let respond = { [weak self] in
            guard let self else { return }
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

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CacheStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// A substitute cache, standing in for the real one through the environment.
private struct StubPageImageCache: PageImageCache {
    let stubbedImage: UIImage

    func cachedImage(for url: URL) -> UIImage? { stubbedImage }

    func image(for url: URL) async throws -> UIImage { stubbedImage }
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
