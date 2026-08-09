//
//  AuthorizedAsyncImage.swift
//  vista_comic
//
//  Drop-in replacement for `AsyncImage` that authenticates like
//  `APIComicRepository` does. `AsyncImage(url:)` always fetches with a plain
//  `URLSession` and has no API for custom headers, so once Cloudflare Access
//  started gating the backend (`remote-access`), every image request it made
//  was silently blocked at the edge even though the JSON requests succeeded —
//  covers and reader pages failed to load while the library still populated.
//  This mirrors `AsyncImage`'s phase-based content builder so call sites are
//  a near-zero-diff swap; see `Shared/CoverImage.swift` and
//  `Features/ComicPage/ComicView.swift`.
//
//  As of `reader-page-prefetch` ticket 01 this view no longer issues its own
//  request: it consumes `PageImageCache` from the environment. `fetchImage`
//  below is unchanged and is now the network primitive the cache calls, so
//  the Cloudflare Access behaviour above — and its regression tests — are
//  untouched by that move.
//

import SwiftUI
import UIKit

struct AuthorizedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    /// Fired alongside a successful `.success` phase with the decoded source
    /// `UIImage`, not just the SwiftUI `Image` rendered into `content`.
    /// `AsyncImagePhase` is a SwiftUI type and can't be extended with a new
    /// case, so this is a separate, optional escape hatch for callers that
    /// need pixel-level access to what was actually decoded (e.g. cropping
    /// a user-drawn selection at full source resolution). Defaults to `nil`
    /// so existing call sites are unaffected.
    var onDecoded: ((UIImage) -> Void)?

    /// The cache this view loads through. Credentials and the session used to
    /// be this view's own initializer parameters; they moved to the cache with
    /// the fetch itself, and no call site ever overrode them.
    @Environment(\.pageImageCache) private var pageImageCache

    /// The phase resolved *asynchronously* so far, or `nil` when nothing has
    /// been resolved yet — in which case `body` falls back to the synchronous
    /// cache lookup below.
    ///
    /// Optional rather than defaulting to `.empty` because "no result yet" and
    /// "loading, show the placeholder" are genuinely different here: the first
    /// still has to consult the cache, and the second must not.
    @State private var phase: AsyncImagePhase?

    init(
        url: URL?,
        onDecoded: ((UIImage) -> Void)? = nil,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.onDecoded = onDecoded
        self.content = content
    }

    var body: some View {
        content(phase ?? synchronouslyResolvedPhase)
            .task(id: url) {
                phase = nil
                guard let url else { return }

                if let resident = pageImageCache.cachedImage(for: url) {
                    // The image is already on screen — `body` above found it
                    // before this task ever ran. Pin it into `phase` so a
                    // later eviction can't flip a visible row back to its
                    // placeholder, and deliver `onDecoded`, which can't be
                    // fired from `body` without mutating state mid-update.
                    phase = .success(Image(uiImage: resident))
                    onDecoded?(resident)
                    return
                }

                do {
                    let loaded = try await pageImageCache.image(for: url)
                    phase = .success(Image(uiImage: loaded))
                    onDecoded?(loaded)
                } catch {
                    if !Task.isCancelled {
                        phase = .failure(error)
                    }
                }
            }
    }

    /// The phase to draw before any asynchronous work has resolved.
    ///
    /// This is the no-flash guarantee, and it works only because it runs here,
    /// during body evaluation, rather than in `.task`. SwiftUI runs a `.task`
    /// *after* the view has already been drawn once, so anything resolved
    /// there — however instantly — is preceded by one frame of the `.empty`
    /// placeholder. Scrolling back to a Page whose bytes were already in hand
    /// would still flash. Reading the cache from `body` means the very first
    /// frame the row draws already contains the image, and the row occupies
    /// its correct height immediately.
    ///
    /// A miss returns `.empty`, so an uncached image behaves exactly as it
    /// always did: placeholder, then success or failure from the task.
    private var synchronouslyResolvedPhase: AsyncImagePhase {
        guard let url, let resident = pageImageCache.cachedImage(for: url) else {
            return .empty
        }
        return .success(Image(uiImage: resident))
    }

    /// The result of a fetch: the SwiftUI `Image` used to render `content`,
    /// and the decoded `UIImage` it was built from, for callers that need
    /// the original source pixels rather than the rendered SwiftUI value.
    struct FetchedImage {
        let image: Image
        let decodedImage: UIImage
    }

    /// Isolated from view state so it's directly testable without rendering.
    static func fetchImage(
        url: URL,
        session: URLSession,
        clientID: String?,
        clientSecret: String?
    ) async throws -> FetchedImage {
        let request = APIConfig.authorizedRequest(url: url, clientID: clientID, clientSecret: clientSecret)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        guard let uiImage = UIImage(data: data) else {
            throw APIError.decoding(
                DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Response body was not a decodable image")
                )
            )
        }
        return FetchedImage(image: Image(uiImage: uiImage), decodedImage: uiImage)
    }
}
