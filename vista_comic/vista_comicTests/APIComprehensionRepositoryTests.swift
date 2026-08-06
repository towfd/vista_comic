//
//  APIComprehensionRepositoryTests.swift
//  vista_comicTests
//
//  Verifies `APIComprehensionRepository` builds each of the six
//  `/comprehensions` requests correctly (method, path, JSON body), decodes
//  `ComprehensionRecord` responses, maps 429 to the daily-cap error, and
//  attaches the Cloudflare Access headers — using a stubbed
//  `URLProtocol`-backed `URLSession`, the same technique as
//  `APIComicRepositoryTests` and `APIComicRepositoryTests`.
//
//  The per-call *path* assertions earn their place: five of the six routes
//  differ only by id and suffix, and they share one `send` helper, so a single
//  wrong argument there would silently point every call at the collection.
//

import Foundation
import Testing

@testable import vista_comic

/// A stub `URLProtocol` that never touches the network.
///
/// File-private and not shared with other suites on purpose — mirrors
/// `APIComicRepositoryTests`'s own stub, whose doc comment explains why:
/// static state races across `@Suite`s Swift Testing may run in parallel.
private final class ComprehensionStubURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var responseBody: Data = Data("{}".utf8)
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        ComprehensionStubURLProtocol.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: ComprehensionStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ComprehensionStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `.serialized` for the same reason `APIComicRepositoryTests` is: the stub's
/// request/response state is static, so tests sharing it must not run in
/// parallel with each other.
@Suite("APIComprehensionRepository", .serialized)
struct APIComprehensionRepositoryTests {
    private static let recordJSON = """
    {
        "id": 7,
        "sourceText": "Xin chào",
        "translatedText": "你好",
        "cloudTranslation": "你好呀",
        "grammarNotes": "g",
        "contextNotes": "c",
        "toneRegister": "t",
        "targetLanguage": "zh-Hant",
        "comicId": "comic-1",
        "chapterId": "chapter-1",
        "pageNumber": 3,
        "comicTitle": "marrymyhusband",
        "chapterTitle": "bai1",
        "status": "ok",
        "isRead": false,
        "useStrongerModel": false,
        "createdAt": "2026-08-05T10:30:00Z"
    }
    """

    private func makeRepository(
        body: String = recordJSON,
        statusCode: Int = 200,
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> APIComprehensionRepository {
        ComprehensionStubURLProtocol.lastRequest = nil
        ComprehensionStubURLProtocol.responseBody = Data(body.utf8)
        ComprehensionStubURLProtocol.statusCode = statusCode

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComprehensionStubURLProtocol.self]
        return APIComprehensionRepository(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration),
            cfAccessClientID: clientID,
            cfAccessClientSecret: clientSecret
        )
    }

    private var lastPath: String? { ComprehensionStubURLProtocol.lastRequest?.url?.path }
    private var lastMethod: String? { ComprehensionStubURLProtocol.lastRequest?.httpMethod }

    // MARK: - Each route hits its own path

    @Test func enqueuePostsToTheCollection() async throws {
        let repository = makeRepository()

        _ = try await repository.enqueue(
            sourceText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3,
            useStrongerModel: true
        )

        #expect(lastMethod == "POST")
        #expect(lastPath == "/comprehensions")
        let request = try #require(ComprehensionStubURLProtocol.lastRequest)
        let body = try #require(request.httpBody ?? bodyStream(from: request))
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        // camelCase on the wire, matching the backend's request model.
        #expect(json["sourceText"] as? String == "Xin chào")
        #expect(json["translatedText"] as? String == "你好")
        #expect(json["comicId"] as? String == "comic-1")
        #expect(json["chapterId"] as? String == "chapter-1")
        #expect(json["pageNumber"] as? Int == 3)
        #expect(json["useStrongerModel"] as? Bool == true)
        // No image ever goes over the wire: the backend re-reads the page.
        #expect(json["cropImageBase64"] == nil)
        #expect(json["pageImageBase64"] == nil)
    }

    @Test func listGetsTheCollection() async throws {
        let repository = makeRepository(body: "[\(Self.recordJSON)]")

        _ = try await repository.list()

        #expect(lastMethod == "GET")
        #expect(lastPath == "/comprehensions")
    }

    @Test func fetchingOneRecordGetsItsOwnPath() async throws {
        let repository = makeRepository()

        _ = try await repository.record(id: 7)

        #expect(lastMethod == "GET")
        #expect(lastPath == "/comprehensions/7")
    }

    @Test func markingReadPatchesItsOwnPath() async throws {
        let repository = makeRepository()

        _ = try await repository.setRead(id: 7, isRead: true)

        #expect(lastMethod == "PATCH")
        #expect(lastPath == "/comprehensions/7")
        let request = try #require(ComprehensionStubURLProtocol.lastRequest)
        let body = try #require(request.httpBody ?? bodyStream(from: request))
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["isRead"] as? Bool == true)
    }

    @Test func retryPostsToTheRetrySubpath() async throws {
        let repository = makeRepository()

        _ = try await repository.retry(id: 7)

        #expect(lastMethod == "POST")
        #expect(lastPath == "/comprehensions/7/retry")
    }

    @Test func deleteTargetsItsOwnPath() async throws {
        let repository = makeRepository(body: "", statusCode: 204)

        try await repository.delete(id: 7)

        #expect(lastMethod == "DELETE")
        #expect(lastPath == "/comprehensions/7")
    }

    // MARK: - Decoding

    @Test func decodesARecordIncludingTheJoinedTitles() async throws {
        let repository = makeRepository()

        let record = try await repository.record(id: 7)

        #expect(record.id == 7)
        #expect(record.status == .ok)
        #expect(record.comicTitle == "marrymyhusband")
        #expect(record.chapterTitle == "bai1")
        // The cloud wording wins once it exists.
        #expect(record.displayedTranslation == "你好呀")
    }

    @Test func decodesNullTitlesForAComicNoLongerInTheLibrary() async throws {
        let body = Self.recordJSON
            .replacingOccurrences(of: "\"marrymyhusband\"", with: "null")
            .replacingOccurrences(of: "\"bai1\"", with: "null")
        let repository = makeRepository(body: body)

        let record = try await repository.record(id: 7)

        #expect(record.comicTitle == nil)
        #expect(record.chapterTitle == nil)
    }

    // MARK: - The one failure the reader cannot fix by retrying

    @Test func enqueueMaps429ToTheDailyCapError() async throws {
        let repository = makeRepository(body: "{\"detail\":\"cap\"}", statusCode: 429)

        await #expect(throws: ComprehensionEnqueueError.dailyCapReached) {
            _ = try await repository.enqueue(
                sourceText: "a", translatedText: "b", targetLanguage: "zh-Hant",
                comicID: "c", chapterID: "ch", pageNumber: 1, useStrongerModel: false
            )
        }
    }

    @Test func retryAlsoMaps429SinceItSpendsARequestToo() async throws {
        let repository = makeRepository(body: "{\"detail\":\"cap\"}", statusCode: 429)

        await #expect(throws: ComprehensionEnqueueError.dailyCapReached) {
            _ = try await repository.retry(id: 7)
        }
    }

    /// Reads must not be mistaken for the cap case: a 429 there is an ordinary
    /// HTTP failure, and telling the reader their budget is spent would be
    /// wrong.
    @Test func readsDoNotClaimTheDailyCapWasReached() async throws {
        let repository = makeRepository(body: "{\"detail\":\"nope\"}", statusCode: 429)

        await #expect(throws: APIError.self) {
            _ = try await repository.record(id: 7)
        }
    }

    @Test func aServerErrorSurfacesAsAnHTTPStatusError() async throws {
        let repository = makeRepository(body: "{}", statusCode: 503)

        await #expect(throws: APIError.self) {
            _ = try await repository.list()
        }
    }

    /// `URLProtocol.request.httpBody` is `nil` when `URLSession` has moved the
    /// body into an upload stream instead.
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

    // MARK: - Cloudflare Access

    @Test func attachesAccessHeadersWhenConfigured() async throws {
        let repository = makeRepository(clientID: "id-123", clientSecret: "secret-456")

        _ = try await repository.record(id: 7)

        let request = try #require(ComprehensionStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id-123")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "secret-456")
    }

    @Test func omitsAccessHeadersWhenUnconfigured() async throws {
        let repository = makeRepository()

        _ = try await repository.record(id: 7)

        let request = try #require(ComprehensionStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }
}
