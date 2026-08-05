//
//  APIComprehenderTests.swift
//  vista_comicTests
//
//  Verifies `APIComprehender` builds `POST /comprehend` requests correctly
//  (method, path, body — including both base64-encoded images and the page
//  image's downscaling), and maps the backend's `status` field / HTTP errors
//  onto `Comprehender`'s success/error cases, using a stubbed
//  `URLProtocol`-backed `URLSession` — same technique as
//  `APITranslationRepositoryTests`/`APIComicRepositoryTests`. No real network
//  call is made.
//

import Testing
import Foundation
import UIKit
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it records the last
/// request it saw and returns a canned response/body so the comprehender's
/// decode step succeeds.
///
/// File-private and not shared with other test suites on purpose — mirrors
/// `APITranslationRepositoryTests`'s `TranslationStubURLProtocol`, whose doc
/// comment explains why: static state races across `@Suite`s Swift Testing
/// may run in parallel with each other.
private final class ComprehenderStubURLProtocol: URLProtocol {
    /// Set by the test before making a call; read back to assert on the
    /// request that was actually built.
    static var lastRequest: URLRequest?
    /// The response body served to every request.
    static var responseBody: Data = Data("{\"status\": \"declined\"}".utf8)
    /// The HTTP status served to every request.
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `URLProtocol` doesn't expose the request body via `request.httpBody`
        // once it's an upload stream, but for a plain in-memory `Data` body
        // (as built by `APIComprehender`) it round-trips fine, so capture
        // `request` as-is.
        ComprehenderStubURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: ComprehenderStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ComprehenderStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("APIComprehender", .serialized)
struct APIComprehenderTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComprehenderStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeComprehender(
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> APIComprehender {
        APIComprehender(
            baseURL: URL(string: "https://api.example.com")!,
            session: makeSession(),
            cfAccessClientID: clientID,
            cfAccessClientSecret: clientSecret
        )
    }

    /// A small solid-color `UIImage` for the selection crop — deliberately
    /// under the 1024pt downscale threshold, so tests can assert the crop
    /// travels unscaled.
    private func makeTestImage(width: CGFloat = 40, height: CGFloat = 20) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static let okResponseJSON = """
    {
        "status": "ok",
        "translation": "你好",
        "grammarNotes": "A simple greeting.",
        "contextNotes": "Spoken directly to the listener.",
        "toneRegister": "Casual."
    }
    """

    private static let declinedResponseJSON = """
    {"status": "declined"}
    """

    // MARK: - Request shape

    @Test func comprehendBuildsPostRequestToComprehendPath() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        _ = try? await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/comprehend")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func comprehendEncodesImagesAndSourceTextInBody() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        _ = try? await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: true
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        let bodyData = try #require(request.httpBody ?? bodyStream(from: request))
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        #expect(body["sourceText"] as? String == "Xin chào")
        #expect(body["targetLanguageCode"] as? String == "zh-Hant")
        #expect(body["useStrongerModel"] as? Bool == true)

        let cropBase64 = try #require(body["cropImageBase64"] as? String)
        let pageBase64 = try #require(body["pageImageBase64"] as? String)
        #expect(!cropBase64.isEmpty)
        #expect(!pageBase64.isEmpty)
        // Both must be valid base64 that decodes into real image bytes.
        #expect(Data(base64Encoded: cropBase64) != nil)
        #expect(Data(base64Encoded: pageBase64) != nil)
    }

    @Test func comprehendSendsUseStrongerModelFalseByDefaultCase() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        _ = try? await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        let bodyData = try #require(request.httpBody ?? bodyStream(from: request))
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(body["useStrongerModel"] as? Bool == false)
    }

    @Test func comprehendDownscalesPageImageLongEdgeButNotTheCrop() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        // Well over the ~1024pt downscale threshold.
        let largePage = makeTestImage(width: 3000, height: 1500)
        let smallCrop = makeTestImage(width: 40, height: 20)

        let comprehender = makeComprehender()
        _ = try? await comprehender.comprehend(
            crop: smallCrop,
            page: largePage,
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        let bodyData = try #require(request.httpBody ?? bodyStream(from: request))
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        let pageBase64 = try #require(body["pageImageBase64"] as? String)
        let pageData = try #require(Data(base64Encoded: pageBase64))
        let decodedPage = try #require(UIImage(data: pageData))
        #expect(max(decodedPage.size.width, decodedPage.size.height) <= 1024)

        let cropBase64 = try #require(body["cropImageBase64"] as? String)
        let cropData = try #require(Data(base64Encoded: cropBase64))
        let decodedCrop = try #require(UIImage(data: cropData))
        // The crop travels at its original resolution — never downscaled.
        // Compared against `smallCrop`'s own pixel dimensions (not the 40x20
        // *point* size it was requested at) since `UIImage(data:)` decodes at
        // scale 1.0, and `smallCrop`'s `.scale` (whatever the current
        // environment's default renderer scale is) may not be 1.0 itself —
        // the crop's actual encoded pixel content must be unchanged, not its
        // point-space representation.
        let originalCropPixels = try #require(smallCrop.cgImage)
        #expect(decodedCrop.size.width == CGFloat(originalCropPixels.width))
        #expect(decodedCrop.size.height == CGFloat(originalCropPixels.height))
    }

    // MARK: - Response mapping: success

    @Test func comprehendReturnsResultOnOkStatus() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.okResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        let result = try await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        #expect(result.translation == "你好")
        #expect(result.grammarNotes == "A simple greeting.")
        #expect(result.contextNotes == "Spoken directly to the listener.")
        #expect(result.toneRegister == "Casual.")
    }

    // MARK: - Response mapping: declined

    @Test func comprehendThrowsDeclinedOnDeclinedStatus() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        await #expect(throws: ComprehensionError.declined) {
            try await comprehender.comprehend(
                crop: makeTestImage(),
                page: makeTestImage(),
                sourceText: "Xin chào",
                targetLanguage: "zh-Hant",
                useStrongerModel: false
            )
        }
    }

    // MARK: - Response mapping: underlying / HTTP errors

    @Test func comprehendThrowsUnderlyingOnServerErrorStatus() async throws {
        ComprehenderStubURLProtocol.responseBody = Data()
        ComprehenderStubURLProtocol.statusCode = 502

        let comprehender = makeComprehender()
        do {
            _ = try await comprehender.comprehend(
                crop: makeTestImage(),
                page: makeTestImage(),
                sourceText: "Xin chào",
                targetLanguage: "zh-Hant",
                useStrongerModel: false
            )
            Issue.record("Expected comprehend to throw on a 502 response")
        } catch let error as ComprehensionError {
            guard case .underlying = error else {
                Issue.record("Expected .underlying, got \(error)")
                return
            }
        }
    }

    @Test func comprehendThrowsUnderlyingOnRateLimitStatus() async throws {
        ComprehenderStubURLProtocol.responseBody = Data()
        ComprehenderStubURLProtocol.statusCode = 429

        let comprehender = makeComprehender()
        do {
            _ = try await comprehender.comprehend(
                crop: makeTestImage(),
                page: makeTestImage(),
                sourceText: "Xin chào",
                targetLanguage: "zh-Hant",
                useStrongerModel: false
            )
            Issue.record("Expected comprehend to throw on a 429 response")
        } catch let error as ComprehensionError {
            guard case .underlying = error else {
                Issue.record("Expected .underlying, got \(error)")
                return
            }
        }
    }

    @Test func comprehendThrowsUnderlyingOnMalformedResponseBody() async throws {
        ComprehenderStubURLProtocol.responseBody = Data("not json".utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        do {
            _ = try await comprehender.comprehend(
                crop: makeTestImage(),
                page: makeTestImage(),
                sourceText: "Xin chào",
                targetLanguage: "zh-Hant",
                useStrongerModel: false
            )
            Issue.record("Expected comprehend to throw on a malformed response body")
        } catch let error as ComprehensionError {
            guard case .underlying = error else {
                Issue.record("Expected .underlying, got \(error)")
                return
            }
        }
    }

    // MARK: - Cloudflare Access headers

    @Test func comprehendAttachesHeadersWhenConfigured() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender(clientID: "test-client-id", clientSecret: "test-client-secret")
        _ = try? await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func comprehendOmitsHeadersWhenUnconfigured() async throws {
        ComprehenderStubURLProtocol.responseBody = Data(Self.declinedResponseJSON.utf8)
        ComprehenderStubURLProtocol.statusCode = 200

        let comprehender = makeComprehender()
        _ = try? await comprehender.comprehend(
            crop: makeTestImage(),
            page: makeTestImage(),
            sourceText: "Xin chào",
            targetLanguage: "zh-Hant",
            useStrongerModel: false
        )

        let request = try #require(ComprehenderStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    /// `URLProtocol.request.httpBody` is `nil` when `URLSession` has moved the
    /// body into an upload stream instead — mirrors
    /// `APITranslationRepositoryTests`'s own `bodyStream(from:)` helper.
    private func bodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
