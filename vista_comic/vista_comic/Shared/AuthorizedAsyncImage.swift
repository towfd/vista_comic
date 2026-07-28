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

import SwiftUI
import UIKit

struct AuthorizedAsyncImage<Content: View>: View {
    let url: URL?
    let session: URLSession
    let clientID: String?
    let clientSecret: String?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        session: URLSession = .shared,
        clientID: String? = APIConfig.cfAccessClientID,
        clientSecret: String? = APIConfig.cfAccessClientSecret,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.session = session
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                phase = .empty
                guard let url else { return }
                do {
                    phase = .success(
                        try await Self.fetchImage(
                            url: url,
                            session: session,
                            clientID: clientID,
                            clientSecret: clientSecret
                        )
                    )
                } catch {
                    if !Task.isCancelled {
                        phase = .failure(error)
                    }
                }
            }
    }

    /// Isolated from view state so it's directly testable without rendering.
    static func fetchImage(
        url: URL,
        session: URLSession,
        clientID: String?,
        clientSecret: String?
    ) async throws -> Image {
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
        return Image(uiImage: uiImage)
    }
}
