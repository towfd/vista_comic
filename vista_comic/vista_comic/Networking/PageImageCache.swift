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
//  Ticket 01 of the feature brought retention plus the synchronous hit path.
//  Ticket 02 adds the prefetch window on top: bounded concurrency, real
//  cancellation, and failure marking. Reserved page heights are a later ticket
//  and are deliberately absent here.
//

import Foundation
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
    ///
    /// This is the *explicit* ask — a row that is actually on screen. It
    /// therefore takes priority over anything the window is fetching further
    /// down, and it always re-attempts a URL that previously failed: the
    /// failure mark exists only to stop `setPrefetchWindow(pageURLs:currentIndex:)`
    /// from looping, never to make a Page the reader reached unloadable.
    func image(for url: URL) async throws -> UIImage

    /// Declares which Pages are worth having in hand, given the chapter's
    /// ordered Page URLs and the 0-based index the reader is currently at.
    ///
    /// Starts what is missing from the window, cancels prefetches that have
    /// left it, and does **not** touch what is already resident — a chapter
    /// change re-seeds the window without clearing the cache.
    ///
    /// Synchronous and non-blocking: safe to call from a scroll callback. The
    /// work it schedules is fire-and-forget by design. It returns nothing and
    /// takes no callback, so there is no path by which prefetching can report
    /// anything back into the Reader — in particular, none by which a Page
    /// fetched ahead of the reader could be mistaken for a Page they read.
    func setPrefetchWindow(pageURLs: [URL], currentIndex: Int)

    /// How tall `url` is relative to its width, from the last time it was
    /// decoded — `nil` for a Page this cache has never held.
    ///
    /// Kept here, next to the images, rather than by the row that displays a
    /// Page, because it has to outlive both things that destroy a row's state:
    /// the `LazyVStack` recycling the row, and this cache evicting the image.
    /// A Page seen once therefore reserves its exact height forever after,
    /// resident or not — which is what stops the reader's content collapsing
    /// when anything (the keyboard, a rotation, a memory warning) rebuilds
    /// rows the byte budget no longer covers.
    ///
    /// Deliberately **not** dropped by eviction or by a memory warning. A
    /// ratio is two words against an image's megabytes, and a purge is exactly
    /// the moment stable heights matter most.
    ///
    /// Synchronous and non-blocking by contract, like `cachedImage(for:)`, and
    /// for the same reason: it is read while a row's `body` is being evaluated.
    func heightRatio(for url: URL) -> CGFloat?
}

// MARK: - The window

/// How far either side of the reader the cache tries to stay ahead.
///
/// Measured against the real library rather than guessed: five Pages ahead is
/// a median of 4.2 screens of content (10th percentile 3.1), comfortably more
/// than normal scrolling consumes. Ten ahead would be 8.3 screens — measurably
/// more memory and more connections for a buffer the reader will not outrun.
enum PagePrefetchWindow {
    static let pagesAhead = 5
    static let pagesBehind = 2

    /// The window's URLs **in request priority order**: the Page the reader is
    /// on first, then the Pages ahead in reading order, then the Pages behind.
    ///
    /// Order matters because the window is larger than the number of fetches
    /// allowed to run at once, so something has to wait — and what waits should
    /// be the Page furthest from where the reader is heading.
    ///
    /// Clamps at both ends of the chapter rather than requesting past the last
    /// Page, and returns nothing for an empty chapter.
    static func urls(in pageURLs: [URL], centredOn currentIndex: Int) -> [URL] {
        guard !pageURLs.isEmpty else { return [] }

        let centre = min(max(currentIndex, 0), pageURLs.count - 1)
        let last = min(centre + pagesAhead, pageURLs.count - 1)
        let first = max(centre - pagesBehind, 0)

        var ordered: [URL] = []
        ordered.reserveCapacity(last - first + 1)
        for index in centre...last {
            ordered.append(pageURLs[index])
        }
        if first < centre {
            for index in stride(from: centre - 1, through: first, by: -1) {
                ordered.append(pageURLs[index])
            }
        }
        return ordered
    }
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
    /// The environment's default (see `PageImageCacheKey`), and what previews
    /// and any screen outside the app's own wiring load through. Shared so a
    /// Page fetched by the Reader is still resident after the Reader is torn
    /// down and re-entered — the cache is never explicitly cleared on chapter
    /// change or on leaving the Reader; the byte budget alone bounds it.
    ///
    /// The running app installs its **own** instance instead, identical but for
    /// knowing where downloaded pages live (`vista_comicApp`). It is created
    /// once at launch and lives as long as the process, so retention across the
    /// app is exactly what it was when this singleton served that role.
    static let shared = MemoryPageImageCache()

    private let store: DecodedImageStore
    private let coordinator = FetchCoordinator()
    /// Consulted before the network (`offline-download` ticket 02). `nil` — the
    /// default, and what `shared` runs with — behaves exactly as this cache did
    /// before downloads existed.
    private let offlineChapters: (any OfflineChapterStore)?
    private let session: URLSession
    private let clientID: String?
    private let clientSecret: String?
    /// Stamped onto each window *synchronously*, at the call site, so the
    /// coordinator can ignore one that arrives out of order.
    ///
    /// `setPrefetchWindow` has to hop onto the coordinator's actor to do its
    /// work, and two hops scheduled back to back are not guaranteed to arrive
    /// in that order. Without this, a fast scroll could end up leaving the
    /// window centred where the reader *was* rather than where they are.
    private let windowGeneration = WindowGeneration()

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
        byteLimit: Int = MemoryPageImageCache.defaultByteLimit,
        offlineChapters: (any OfflineChapterStore)? = nil
    ) {
        self.offlineChapters = offlineChapters
        self.session = session
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.store = DecodedImageStore(byteLimit: byteLimit)
    }

    func cachedImage(for url: URL) -> UIImage? {
        store.image(for: url)
    }

    func heightRatio(for url: URL) -> CGFloat? {
        store.heightRatio(for: url)
    }

    func image(for url: URL) async throws -> UIImage {
        // Checked here, before the actor hop, so a sequential second ask for
        // an already-resident URL costs nothing and issues no request.
        if let resident = store.image(for: url) {
            return resident
        }
        return try await coordinator.image(for: url, fetch: fetchOperation)
    }

    func setPrefetchWindow(pageURLs: [URL], currentIndex: Int) {
        let window = PagePrefetchWindow.urls(in: pageURLs, centredOn: currentIndex)
        // Resident Pages are filtered out here rather than inside the
        // coordinator, because the store is the half of the cache that can be
        // read without `await` — so "what is still missing?" costs nothing and
        // sliding the window forward asks only for newly-entered Pages.
        let missing = window.filter { store.image(for: $0) == nil }
        let generation = windowGeneration.next()
        let fetch = fetchOperation

        Task {
            await coordinator.setWindow(
                window,
                missing: missing,
                generation: generation,
                fetch: fetch
            )
        }
    }

    /// The one way this cache turns a URL into a decoded, stored image.
    ///
    /// Captured as a value so both the explicit ask and the window reconciler
    /// run *exactly* the same fetch, and so the detached tasks the coordinator
    /// spawns never have to reach back into this object.
    private var fetchOperation: @Sendable (URL) async throws -> UIImage {
        let store = self.store
        let session = self.session
        let clientID = self.clientID
        let clientSecret = self.clientSecret
        let offlineChapters = self.offlineChapters

        return { url in
            // The disk goes in front of the network, and nowhere else. Every
            // caller — the explicit ask, the prefetch window, a cover — reaches
            // the network through this one closure, so one step here is the
            // whole of offline reading: the Reader gains no offline code path,
            // and there is therefore no second way for it to be wrong.
            //
            // It runs while online too, which is the point rather than a side
            // effect: a downloaded page is faster and cheaper from disk than
            // from a server that is answering perfectly well.
            if let data = offlineChapters?.pageData(for: url),
               let downloaded = UIImage(data: data) {
                let decoded = Self.forcedToDecode(downloaded)
                store.insert(decoded, for: url)
                return decoded
            }

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
            // Nothing is written back to the disk store here, deliberately: a
            // page merely read is not a page the reader chose to keep, and the
            // moment it were, the download list, the cap and what is actually
            // on the device would stop agreeing.
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
    /// Height-to-width ratio per URL, from the last decode.
    ///
    /// A plain dictionary rather than a second `NSCache` on purpose: this must
    /// **not** be evicted. `NSCache` drops entries on its own schedule, which
    /// would silently reintroduce the collapsing content this exists to
    /// prevent, and at the worst possible moment — under memory pressure, when
    /// every image has just gone and every row is rebuilding from nothing.
    /// A `CGFloat` per Page ever read is negligible beside a single decoded
    /// Page, so there is nothing here worth reclaiming.
    private var heightRatios: [URL: CGFloat] = [:]
    /// Guards `heightRatios` only. `NSCache` is already thread-safe; the
    /// dictionary alongside it is not, and it is read from `body` on the main
    /// thread while fetches write to it from background threads.
    private let ratioLock = NSLock()

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

    func heightRatio(for url: URL) -> CGFloat? {
        ratioLock.withLock { heightRatios[url] }
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: Self.decodedByteCount(of: image))
        if let ratio = Self.heightRatio(of: image) {
            ratioLock.withLock { heightRatios[url] = ratio }
        }
    }

    /// Releases the images. The recorded proportions stay — see `heightRatios`.
    func removeAll() {
        cache.removeAllObjects()
    }

    /// How tall this image is relative to its width. `nil` for a degenerate
    /// image, so a zero width can never divide into the reader's layout.
    private static func heightRatio(of image: UIImage) -> CGFloat? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return size.height / size.width
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

/// The half of the cache that owns work in progress: what is being fetched,
/// who is waiting on it, which Pages the window wants, and cancellation.
///
/// Actor-isolated so "is this URL already being fetched?" can be asked and
/// answered without a lock. Only ever reached from `async` callers, so its
/// `await` requirement costs nothing — unlike the store, which had to be
/// readable from a `body`.
private actor FetchCoordinator {
    /// At most four fetches run at once.
    ///
    /// The library's Pages average 94 KB, so a fetch costs round-trip latency
    /// rather than bandwidth: four in flight hides that latency without
    /// saturating either the connection or the decoder. Everything past the
    /// fourth queues, and the queue is served by rank rather than by arrival.
    private let maxConcurrentFetches = 4

    /// The rank given to a Page the reader is actually looking at, so it is
    /// always served before any prefetch — including prefetches that were
    /// queued before it.
    private static let landedPageRank = -1

    private struct Fetch {
        let id: UUID
        let task: Task<UIImage, any Error>
        /// How many callers are awaiting this URL through `image(for:)` — i.e.
        /// rows actually on screen, as opposed to the window reaching ahead.
        /// A fetch with any is never cancelled by the window moving on.
        var directWaiters: Int
        /// Lower runs sooner. See `landedPageRank`.
        var rank: Int
    }

    /// A fetch that has been admitted but is waiting for one of the four slots.
    private struct SlotWaiter {
        let id: UUID
        let url: URL
        let continuation: CheckedContinuation<Void, any Error>
    }

    private enum Outcome {
        case succeeded
        case failed
        case cancelled
    }

    private var fetches: [URL: Fetch] = [:]
    private var slotWaiters: [SlotWaiter] = []
    private var activeFetches = 0

    /// URLs whose last attempt failed.
    ///
    /// Consulted **only** by the window reconciler, and that asymmetry is the
    /// whole point. Without the mark the reconciler would see "not resident,
    /// not in flight", re-request immediately, fail again, and loop — turning
    /// a dead network into a request storm that burns battery. With it, a
    /// failed Page is simply left alone until the reader does something about
    /// it: `image(for:)` clears the mark on the way in, so both tapping the
    /// Reader's failure placeholder and scrolling to the Page genuinely
    /// re-request.
    private var failedURLs: Set<URL> = []

    private var appliedWindowGeneration = 0

    // MARK: The explicit ask

    /// Returns the image for `url`, running `fetch` only if no other caller is
    /// already fetching it. Concurrent askers all await the same task, so the
    /// same Page requested twice at once costs one network request.
    func image(
        for url: URL,
        fetch: @escaping @Sendable (URL) async throws -> UIImage
    ) async throws -> UIImage {
        failedURLs.remove(url)

        do {
            return try await joinOrStart(url: url, fetch: fetch)
        } catch {
            // A prefetch this caller joined can be cancelled by the window
            // sliding away in the instant before the join was recorded. That
            // must not surface to a row on screen as a failure, so the ask is
            // made once more — as its own fetch this time, since the cancelled
            // one has already removed itself.
            guard Self.isCancellation(error) else { throw error }
            try Task.checkCancellation()
            return try await joinOrStart(url: url, fetch: fetch)
        }
    }

    private func joinOrStart(
        url: URL,
        fetch: @escaping @Sendable (URL) async throws -> UIImage
    ) async throws -> UIImage {
        let task: Task<UIImage, any Error>
        if let existing = fetches[url] {
            fetches[url]?.directWaiters += 1
            // Promotes a Page that was being prefetched and has now been
            // reached: it jumps the queue instead of waiting behind Pages the
            // reader has already scrolled past.
            fetches[url]?.rank = Self.landedPageRank
            task = existing.task
        } else {
            task = startFetch(
                url: url,
                rank: Self.landedPageRank,
                directWaiters: 1,
                fetch: fetch
            )
        }

        defer { fetches[url]?.directWaiters -= 1 }
        return try await task.value
    }

    // MARK: The window

    /// Reconciles what is being fetched against what the window now wants.
    ///
    /// `missing` is `window` minus whatever is already resident, computed by
    /// the caller before the hop onto this actor.
    func setWindow(
        _ window: [URL],
        missing: [URL],
        generation: Int,
        fetch: @escaping @Sendable (URL) async throws -> UIImage
    ) {
        // A window that lost the race to a newer one is not merely redundant:
        // applying it would cancel the newer one's fetches.
        guard generation > appliedWindowGeneration else { return }
        appliedWindowGeneration = generation

        let wanted = Set(window)
        for (url, fetchInProgress) in fetches
        where !wanted.contains(url) && fetchInProgress.directWaiters == 0 {
            // Removed before cancelling so an explicit ask arriving next can
            // start a clean fetch rather than join a dying one. The cancelled
            // task's own bookkeeping no-ops on the id mismatch.
            fetches[url] = nil
            fetchInProgress.task.cancel()
        }

        for (rank, url) in missing.enumerated() {
            guard fetches[url] == nil, !failedURLs.contains(url) else { continue }
            _ = startFetch(url: url, rank: rank, fetch: fetch)
        }
    }

    // MARK: Running the work

    private func startFetch(
        url: URL,
        rank: Int,
        directWaiters: Int = 0,
        fetch: @escaping @Sendable (URL) async throws -> UIImage
    ) -> Task<UIImage, any Error> {
        let id = UUID()
        // The slot is claimed here, synchronously and in rank order, rather
        // than by whichever detached task first reaches this actor — otherwise
        // *which* four of the window's eight Pages start would come down to
        // scheduling luck.
        let admitted = activeFetches < maxConcurrentFetches
        if admitted { activeFetches += 1 }

        // Detached rather than a plain `Task`, which would inherit this
        // actor's isolation and run the fetch *and the forced decode* on the
        // actor's executor, serialising every fetch behind one another.
        // Detached also means it does not inherit cancellation, which is
        // exactly why the handle is kept: cancelling is now explicit.
        let task = Task.detached(priority: rank == Self.landedPageRank ? .userInitiated : .utility) {
            if !admitted {
                do {
                    try await self.waitForSlot(url: url, id: id)
                } catch {
                    // Cancelled while queued: it never held a slot, so there
                    // is none to give back.
                    await self.finish(
                        url: url, id: id, outcome: .cancelled, releasingSlot: false
                    )
                    throw error
                }
            }

            do {
                let image = try await fetch(url)
                await self.finish(url: url, id: id, outcome: .succeeded, releasingSlot: true)
                return image
            } catch {
                await self.finish(
                    url: url,
                    id: id,
                    outcome: Self.isCancellation(error) ? .cancelled : .failed,
                    releasingSlot: true
                )
                throw error
            }
        }

        fetches[url] = Fetch(id: id, task: task, directWaiters: directWaiters, rank: rank)
        return task
    }

    private func waitForSlot(url: URL, id: UUID) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                slotWaiters.append(SlotWaiter(id: id, url: url, continuation: continuation))
            }
        } onCancel: {
            // Hops back onto this actor, which cannot happen before the
            // continuation above is registered: registering it is the last
            // thing done before suspending.
            Task { await self.cancelSlotWaiter(id: id) }
        }
    }

    private func cancelSlotWaiter(id: UUID) {
        guard let index = slotWaiters.firstIndex(where: { $0.id == id }) else { return }
        slotWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func finish(url: URL, id: UUID, outcome: Outcome, releasingSlot: Bool) {
        // Unconditional: the slot belonged to this task whatever has since
        // happened to the entry.
        if releasingSlot { releaseSlot() }

        // A newer attempt for the same URL is already running — leave it be.
        guard fetches[url]?.id == id else { return }
        fetches[url] = nil

        switch outcome {
        case .succeeded:
            failedURLs.remove(url)
        case .failed:
            failedURLs.insert(url)
        case .cancelled:
            // Cancelling is not failing: a Page dropped because the reader
            // scrolled past must still be fetchable when they scroll back.
            break
        }
    }

    private func releaseSlot() {
        guard let next = nextSlotWaiterIndex() else {
            activeFetches -= 1
            return
        }
        // Handed straight over rather than released and re-claimed, so the
        // count never dips and a burst of new work cannot slip in ahead of
        // something already waiting.
        slotWaiters.remove(at: next).continuation.resume()
    }

    /// The queued fetch with the lowest rank, so the Page nearest where the
    /// reader is heading runs next regardless of when it was queued.
    private func nextSlotWaiterIndex() -> Int? {
        guard !slotWaiters.isEmpty else { return nil }

        var bestIndex = 0
        var bestRank = rank(of: slotWaiters[0])
        for index in 1..<slotWaiters.count {
            let candidate = rank(of: slotWaiters[index])
            if candidate < bestRank {
                bestIndex = index
                bestRank = candidate
            }
        }
        return bestIndex
    }

    private func rank(of waiter: SlotWaiter) -> Int {
        fetches[waiter.url]?.rank ?? Int.max
    }

    /// Whether `error` means "this was called off" rather than "this failed".
    ///
    /// Both spellings matter: a task cancelled before it reaches the network
    /// throws `CancellationError`, while one cancelled mid-request surfaces
    /// `URLSession`'s `URLError.cancelled`. Treating the latter as a failure
    /// would mark a Page the reader merely scrolled past as broken, and the
    /// window would then refuse to fetch it when they scrolled back.
    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

// MARK: - Window ordering

/// A monotonically increasing stamp, taken synchronously so ordering is
/// decided at the call site rather than by which actor hop lands first.
private final class WindowGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
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
