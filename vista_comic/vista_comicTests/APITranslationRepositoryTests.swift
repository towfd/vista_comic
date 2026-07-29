//
//  APITranslationRepositoryTests.swift
//  vista_comicTests
//
//  Verifies `APITranslationRepository` builds `save`/`list` requests
//  correctly (method, path, JSON body) and decodes `SavedTranslation`
//  responses correctly, using a stubbed `URLProtocol`-backed `URLSession` —
//  same technique as `APIComicRepositoryTests`. Also verifies Cloudflare
//  Access Service Token headers are attached the same way `APIComicRepository`
//  attaches them, since both repositories route every request through the
//  same `APIConfig.authorizedRequest` construction point.
//

import Testing
import Foundation
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it records the last
/// request it saw and returns a canned response/body so the repository's
/// decode step succeeds.
///
/// File-private and not shared with other test suites on purpose — mirrors
/// `APIComicRepositoryTests`'s `RepositoryStubURLProtocol`, whose doc comment
/// explains why: static state races across `@Suite`s Swift Testing may run
/// in parallel with each other.
private final class TranslationStubURLProtocol: URLProtocol {
    /// Set by the test before making a call; read back to assert on the
    /// request that was actually built.
    static var lastRequest: URLRequest?
    /// The response body served to every request.
    static var responseBody: Data = Data("[]".utf8)
    /// The HTTP status served to every request.
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `URLProtocol` doesn't expose the request body via `request.httpBody`
        // once it's an upload stream, but for a plain in-memory `Data` body
        // (as built by `APITranslationRepository`) it round-trips fine, so
        // capture `request` as-is.
        TranslationStubURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: TranslationStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: TranslationStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("APITranslationRepository", .serialized)
struct APITranslationRepositoryTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRepository(
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> APITranslationRepository {
        APITranslationRepository(
            baseURL: URL(string: "https://api.example.com")!,
            session: makeSession(),
            cfAccessClientID: clientID,
            cfAccessClientSecret: clientSecret
        )
    }

    private static let sampleResponseJSON = """
    {
        "id": 42,
        "originalText": "Xin chào",
        "translatedText": "你好",
        "targetLanguage": "zh-Hant",
        "comicId": "comic-1",
        "chapterId": "chapter-1",
        "pageNumber": 3,
        "savedAt": "2026-01-15T10:30:00Z"
    }
    """

    // MARK: - save()

    @Test func saveBuildsPostRequestWithEncodedBody() async throws {
        TranslationStubURLProtocol.responseBody = Data(Self.sampleResponseJSON.utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository()
        _ = try await repository.save(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3
        )

        let request = try #require(TranslationStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/translations")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(request.httpBody ?? bodyStream(from: request))
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(body["originalText"] as? String == "Xin chào")
        #expect(body["translatedText"] as? String == "你好")
        #expect(body["targetLanguage"] as? String == "zh-Hant")
        #expect(body["comicId"] as? String == "comic-1")
        #expect(body["chapterId"] as? String == "chapter-1")
        #expect(body["pageNumber"] as? Int == 3)
    }

    @Test func saveDecodesResponseIntoSavedTranslation() async throws {
        TranslationStubURLProtocol.responseBody = Data(Self.sampleResponseJSON.utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository()
        let saved = try await repository.save(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3
        )

        #expect(saved.id == 42)
        #expect(saved.originalText == "Xin chào")
        #expect(saved.translatedText == "你好")
        #expect(saved.targetLanguage == "zh-Hant")
        #expect(saved.comicID == "comic-1")
        #expect(saved.chapterID == "chapter-1")
        #expect(saved.pageNumber == 3)

        let expectedDate = try #require(
            ISO8601DateFormatter().date(from: "2026-01-15T10:30:00Z")
        )
        #expect(saved.savedAt == expectedDate)
    }

    @Test func saveAttachesHeadersWhenConfigured() async throws {
        TranslationStubURLProtocol.responseBody = Data(Self.sampleResponseJSON.utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        _ = try await repository.save(
            originalText: "a",
            translatedText: "b",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1
        )

        let request = try #require(TranslationStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func saveOmitsHeadersWhenUnconfigured() async throws {
        TranslationStubURLProtocol.responseBody = Data(Self.sampleResponseJSON.utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository()
        _ = try await repository.save(
            originalText: "a",
            translatedText: "b",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1
        )

        let request = try #require(TranslationStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func saveThrowsHTTPStatusErrorOnServerFailure() async throws {
        TranslationStubURLProtocol.responseBody = Data()
        TranslationStubURLProtocol.statusCode = 503

        let repository = makeRepository()
        await #expect(throws: APIError.self) {
            try await repository.save(
                originalText: "a",
                translatedText: "b",
                targetLanguage: "zh-Hant",
                comicID: "comic-1",
                chapterID: "chapter-1",
                pageNumber: 1
            )
        }
    }

    // MARK: - list()

    @Test func listBuildsGetRequestToTranslationsPath() async throws {
        TranslationStubURLProtocol.responseBody = Data("[]".utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository()
        _ = try await repository.list()

        let request = try #require(TranslationStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/translations")
    }

    @Test func listAttachesHeadersWhenConfigured() async throws {
        TranslationStubURLProtocol.responseBody = Data("[]".utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        _ = try await repository.list()

        let request = try #require(TranslationStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func listDecodesResponseIntoSavedTranslations() async throws {
        TranslationStubURLProtocol.responseBody = Data("[\(Self.sampleResponseJSON)]".utf8)
        TranslationStubURLProtocol.statusCode = 200

        let repository = makeRepository()
        let saved = try await repository.list()

        #expect(saved.count == 1)
        #expect(saved.first?.id == 42)
        #expect(saved.first?.originalText == "Xin chào")
        #expect(saved.first?.comicID == "comic-1")
        #expect(saved.first?.chapterID == "chapter-1")
        #expect(saved.first?.pageNumber == 3)
    }

    @Test func listThrowsHTTPStatusErrorOnServerFailure() async throws {
        TranslationStubURLProtocol.responseBody = Data()
        TranslationStubURLProtocol.statusCode = 503

        let repository = makeRepository()
        await #expect(throws: APIError.self) {
            try await repository.list()
        }
    }

    /// `URLProtocol.request.httpBody` is `nil` when `URLSession` has moved the
    /// body into an upload stream instead — not observed with `APITranslationRepository`'s
    /// small in-memory bodies in practice, but this keeps `saveBuildsPostRequestWithEncodedBody`
    /// robust rather than assuming the exact transport detail.
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
