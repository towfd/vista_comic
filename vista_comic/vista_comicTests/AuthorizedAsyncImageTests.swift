//
//  AuthorizedAsyncImageTests.swift
//  vista_comicTests
//
//  Regression coverage for the bug where covers/reader pages failed to load
//  once Cloudflare Access started gating the backend: `AsyncImage(url:)` has
//  no way to attach the Service Token headers, so every image request was
//  blocked at the edge (confirmed live: a request with no headers came back
//  403, the same request with headers came back 200 image/jpeg) even though
//  the JSON API calls succeeded. AuthorizedAsyncImage.fetchImage is the fix;
//  these tests exercise it directly, without rendering the view.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it records the last
/// request it saw and returns a canned response/body.
///
/// File-private and not shared with `APIComicRepositoryTests` on purpose —
/// see the comment on that file's identically-shaped stub for why: a shared
/// stub's static state raced across the two suites, since Swift Testing may
/// run different `@Suite`s in parallel with each other even though
/// `.serialized` only keeps tests *within* one suite sequential.
private final class ImageStubURLProtocol: URLProtocol {
    /// Set by the test before making a call; read back to assert on headers.
    static var lastRequest: URLRequest?
    /// The response body served to every request.
    static var responseBody: Data = Data()
    /// The HTTP status served to every request.
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        ImageStubURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: ImageStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ImageStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("AuthorizedAsyncImage Cloudflare Access headers", .serialized)
struct AuthorizedAsyncImageTests {
    /// A minimal valid 1x1 PNG, so `UIImage(data:)` succeeds.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private static let mediaURL = URL(string: "https://api.example.com/media/comic/chapter/1")!

    @Test func attachesHeadersWhenConfigured() async throws {
        ImageStubURLProtocol.responseBody = Self.onePixelPNG
        ImageStubURLProtocol.statusCode = 200

        _ = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
            url: Self.mediaURL,
            session: ImageStubURLProtocol.makeSession(),
            clientID: "test-client-id",
            clientSecret: "test-client-secret"
        )

        let request = try #require(ImageStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func omitsHeadersWhenUnconfigured() async throws {
        ImageStubURLProtocol.responseBody = Self.onePixelPNG
        ImageStubURLProtocol.statusCode = 200

        _ = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
            url: Self.mediaURL,
            session: ImageStubURLProtocol.makeSession(),
            clientID: nil,
            clientSecret: nil
        )

        let request = try #require(ImageStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func succeedsWithValidImageAndHeaders() async throws {
        ImageStubURLProtocol.responseBody = Self.onePixelPNG
        ImageStubURLProtocol.statusCode = 200

        // Doesn't throw — the exact "headers present, backend returns the
        // image" path that was broken before this fix.
        _ = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
            url: Self.mediaURL,
            session: ImageStubURLProtocol.makeSession(),
            clientID: "test-client-id",
            clientSecret: "test-client-secret"
        )
    }

    /// Reproduces the actual production failure mode: Cloudflare Access
    /// rejects an unauthenticated request with a non-2xx status (observed
    /// live as 403 with an HTML body, not image bytes).
    @Test func throwsOnNonSuccessStatus() async throws {
        ImageStubURLProtocol.responseBody = Data("<html>blocked</html>".utf8)
        ImageStubURLProtocol.statusCode = 403

        do {
            _ = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
                url: Self.mediaURL,
                session: ImageStubURLProtocol.makeSession(),
                clientID: nil,
                clientSecret: nil
            )
            Issue.record("Expected fetchImage to throw on a 403 response")
        } catch APIError.httpStatus(let code) {
            #expect(code == 403)
        }
    }

    @Test func throwsWhenBodyIsNotAnImage() async throws {
        ImageStubURLProtocol.responseBody = Data("not an image".utf8)
        ImageStubURLProtocol.statusCode = 200

        await #expect(throws: (any Error).self) {
            _ = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
                url: Self.mediaURL,
                session: ImageStubURLProtocol.makeSession(),
                clientID: "test-client-id",
                clientSecret: "test-client-secret"
            )
        }
    }
}
