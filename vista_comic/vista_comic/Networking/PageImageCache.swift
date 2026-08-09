//
//  PageImageCache.swift
//  vista_comic
//
//  The image seam for the `reader-page-prefetch` feature, mirroring
//  `ComicRepository`/`OCRRecognizer`/`Translator`'s pattern: `AuthorizedAsyncImage`
//  depends on this protocol, not on a concrete cache, so previews and tests
//  can substitute their own through the environment.
//
//  Before this existed there was no cache anywhere in the image path — the
//  shared `URLCache` the networking layer falls back on is far too small for
//  Page-sized images and the backend sends no caching directives, so every
//  appearance of a Page (scrolling back up, re-entering a chapter, a cover
//  scrolling back into view) was a fresh download *and* a fresh
//  full-resolution decode.
//
//  Ticket 01 of the feature: retention plus the synchronous hit path. The
//  prefetch window and reserved page heights are later tickets and are
//  deliberately absent here.
//

import SwiftUI
import UIKit

/// Fetches, decodes and retains images in memory, keyed by URL.
///
/// Has no opinion about what an image depicts: Reader Pages and Library
/// covers share one instance and one budget.
///
/// The two lookups are **not** redundant. `cachedImage(for:)` exists so a
/// SwiftUI `body` can discover an already-resident image *while the row is
/// being described*, which `image(for:)` can never do — see the note on
/// `MemoryPageImageCache` for why that distinction is the whole point.
protocol PageImageCache: Sendable {
    /// The decoded image for `url` if it is resident right now, `nil`
    /// otherwise.
    ///
    /// Synchronous and non-blocking by contract, and safe to call from any
    /// thread including the main thread mid-layout. Never starts a fetch: a
    /// `nil` here means "not in hand", not "not obtainable".
    func cachedImage(for url: URL) -> UIImage?

    /// The decoded image for `url`, fetching and storing it if it is not
    /// already resident.
    ///
    /// Concurrent callers asking for the same URL share a single network
    /// request rather than issuing one each.
    func image(for url: URL) async throws -> UIImage
}

// MARK: - Live implementation

/// The app's in-memory image cache.
///
/// Deliberately built from **two pieces** rather than one actor:
///
/// - `DecodedImageStore`, a thread-safe container any thread can read
///   *synchronously*, and
/// - `FetchCoordinator`, an actor that owns what is in flight.
///
/// The split exists for one reason, and it is the reason this type achieves
/// its goal: **reading an actor's state from outside always requires `await`,
/// and `await` cannot happen while a SwiftUI view's body is being evaluated.**
/// An actor-only cache would force even a guaranteed hit through the
/// after-first-draw path — the row is drawn once showing its placeholder,
/// *then* the task resumes with the image — which is exactly the flash this
/// feature removes. The cost is that the store's thread safety is its own
/// responsibility rather than the actor's; that trade is accepted.
///
/// Memory only. Nothing is written to disk, and nothing survives launch.
final class MemoryPageImageCache: PageImageCache {
    /// The instance the app runs on, and the environment's default (see
    /// `PageImageCacheKey`). Shared so a Page fetched by the Reader is still
    /// resident after the Reader is torn down and re-entered — the cache is
    /// never explicitly cleared on chapter change or on leaving the Reader;
    /// the byte budget alone bounds it.
    static let shared = MemoryPageImageCache()

    private let store: DecodedImageStore
    private let coordinator = FetchCoordinator()
    private let session: URLSession
    private let clientID: String?
    private let clientSecret: String?

    /// Roughly 150 MB of decoded pixels.
    ///
    /// Every Page in this library is the same width, so a Page's decoded size
    /// is proportional to its on-screen height — which makes a byte budget
    /// automatically a consistent budget of *reading distance*, with no height
    /// arithmetic anywhere. It self-adjusts between a run of tall Pages and a
    /// run of thin slices. At the library's median Page height this holds
    /// several times more than the prefetch window will ask for, leaving room
    /// for scrolling back, chapter switching and covers.
    static let defaultByteLimit = 150 * 1024 * 1024

    init(
        session: URLSession = .shared,
        clientID: String? = APIConfig.cfAccessClientID,
        clientSecret: String? = APIConfig.cfAccessClientSecret,
        byteLimit: Int = MemoryPageImageCache.defaultByteLimit
    ) {
        self.session = session
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.store = DecodedImageStore(byteLimit: byteLimit)
    }

    func cachedImage(for url: URL) -> UIImage? {
        store.image(for: url)
    }

    func image(for url: URL) async throws -> UIImage {
        // Checked here, before the actor hop, so a sequential second ask for
        // an already-resident URL costs nothing and issues no request.
        if let resident = store.image(for: url) {
            return resident
        }

        let store = self.store
        let session = self.session
        let clientID = self.clientID
        let clientSecret = self.clientSecret

        return try await coordinator.image(for: url) { url in
            // `AuthorizedAsyncImage.fetchImage` stays the one place a media
            // request is built, so the Cloudflare Access behaviour — and the
            // regression tests guarding it — survive this change untouched.
            let fetched = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
                url: url,
                session: session,
                clientID: clientID,
                clientSecret: clientSecret
            )
            let decoded = Self.forcedToDecode(fetched.decodedImage)
            store.insert(decoded, for: url)
            return decoded
        }
    }

    /// Forces `image`'s pixels to be decoded now, on whatever background
    /// thread this is running on, by redrawing it into a bitmap this function
    /// owns.
    ///
    /// `UIImage(data:)` only parses the header; the expensive decode is
    /// deferred until the image is first *drawn* — on the main thread, in the
    /// middle of rendering a frame. Paying it here is part of the win rather
    /// than an optimisation detail, because a cached image is displayed during
    /// a scroll, which is precisely when the main thread has no time to spare.
    ///
    /// Drawing into an explicit `CGContext` rather than calling
    /// `UIImage.preparingForDisplay()`, which was measured to be
    /// non-deterministic here: it never returned `nil`, but under load it
    /// handed back an image still backed by the original encoded data (its
    /// `CGImage` kept the source's `utType`), leaving the decode to happen at
    /// draw time after all. `CGContext.draw` has no such discretion — every
    /// pixel must be produced to fill the buffer — so this cannot silently
    /// no-op.
    ///
    /// Decodes at **full source resolution**, using the source's own pixel
    /// dimensions: the selection-crop path reads source pixels, so
    /// downsampling would silently degrade recognition quality. Scale and
    /// orientation are carried over unchanged, so `UIImage.size` and
    /// `CGImage.width`/`.height` mean exactly what they did before — the crop
    /// mapping depends on both.
    ///
    /// Returns the original image if a bitmap context can't be made for it,
    /// which costs a main-thread decode but is never wrong.
    private static func forcedToDecode(_ image: UIImage) -> UIImage {
        guard let source = image.cgImage else { return image }

        let width = source.width
        let height = source.height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                // Zero lets Core Graphics pick its own aligned row stride.
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return image
        }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decoded = context.makeImage() else { return image }

        return UIImage(cgImage: decoded, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - The synchronously readable store

/// The half of the cache that any thread may read without `await`.
///
/// `NSCache` is thread-safe by contract, which is the property being bought
/// here — it is what lets `cachedImage(for:)` be called from a `body`. Its
/// eviction *order* is documented as unspecified (approximately
/// least-recently-used in practice); the enforced guarantee is the byte
/// budget, and no caller may depend on which particular entry went first.
private final class DecodedImageStore: @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()
    private var memoryWarningObserver: (any NSObjectProtocol)?

    init(byteLimit: Int) {
        cache.totalCostLimit = byteLimit

        // Reading must never put the device under pressure, so everything is
        // released the moment the system says it is short of memory. `NSCache`
        // does some of this on its own, but only for discardable content and
        // on no promised schedule; this makes the release explicit.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.removeAll()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: Self.decodedByteCount(of: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// What this image actually costs in memory once decoded — the budget is
    /// bytes, not a count, because Page heights in this library vary 64-fold
    /// and a count would mean wildly different memory for the same number of
    /// Pages.
    private static func decodedByteCount(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            // No backing bitmap to measure (e.g. a vector-backed image);
            // estimate from the point size at 4 bytes per pixel.
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            return Int(pixelWidth * pixelHeight) * 4
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

// MARK: - The in-flight coordinator

/// The half of the cache that owns work in progress.
///
/// Actor-isolated so "is this URL already being fetched?" can be asked and
/// answered without a lock. Only ever reached from `async` callers, so its
/// `await` requirement costs nothing — unlike the store, which had to be
/// readable from a `body`.
private actor FetchCoordinator {
    /// The fetch currently running for each URL, so callers can join one
    /// rather than start another.
    private var inFlight: [URL: Task<UIImage, any Error>] = [:]

    /// Returns the image for `url`, running `fetch` only if no other caller is
    /// already fetching it. Concurrent askers all await the same task, so the
    /// same Page requested twice at once costs one network request.
    func image(
        for url: URL,
        fetch: @escaping @Sendable (URL) async throws -> UIImage
    ) async throws -> UIImage {
        if let existing = inFlight[url] {
            return try await existing.value
        }

        // Detached rather than a plain `Task`, which would inherit this
        // actor's isolation and run the fetch *and the forced decode* on the
        // actor's executor, serialising every fetch behind one another.
        let task = Task.detached(priority: .userInitiated) {
            try await fetch(url)
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            return image
        } catch {
            // Cleared on failure too, so a retry genuinely re-requests rather
            // than replaying the same failure from a finished task.
            inFlight[url] = nil
            throw error
        }
    }
}

// MARK: - Environment injection

private struct PageImageCacheKey: EnvironmentKey {
    /// The live shared cache, deliberately — not a preview-safe stand-in the
    /// way `ComicRepositoryKey`'s default is.
    ///
    /// Two reasons. It means `AuthorizedAsyncImage` reads a working cache with
    /// no app-level wiring and no call-site change anywhere. And it is
    /// harmless in a preview: the cache only ever touches the network for a
    /// URL a view actually asks for, so a preview with no real URLs makes no
    /// requests. Previews and tests that need different behaviour substitute
    /// their own through `\.pageImageCache`.
    static let defaultValue: any PageImageCache = MemoryPageImageCache.shared
}

extension EnvironmentValues {
    /// The cache the current view tree loads its images through.
    var pageImageCache: any PageImageCache {
        get { self[PageImageCacheKey.self] }
        set { self[PageImageCacheKey.self] = newValue }
    }
}
