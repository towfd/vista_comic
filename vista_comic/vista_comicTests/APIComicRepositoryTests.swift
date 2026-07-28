//
//  APIComicRepositoryTests.swift
//  vista_comicTests
//
//  Verifies that `APIComicRepository` attaches Cloudflare Access Service
//  Token headers (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) to every
//  outgoing request when configured, and adds no headers at all when the
//  credentials are unset — the no-op path local/simulator dev relies on.
//

import Testing
import Foundation
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it records the last
/// request it saw and returns a canned response/body so the repository's
/// decode step succeeds.
private final class StubURLProtocol: URLProtocol {
    /// Set by the test before making a call; read back to assert on headers.
    static var lastRequest: URLRequest?
    /// The response body served to every request. Defaults to an empty JSON
    /// array, which satisfies `[Comic]` decoding for `library()`.
    static var responseBody: Data = Data("[]".utf8)
    /// The HTTP status served to every request.
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("APIComicRepository Cloudflare Access headers", .serialized)
struct APIComicRepositoryTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRepository(
        clientID: String?,
        clientSecret: String?
    ) -> APIComicRepository {
        APIComicRepository(
            baseURL: URL(string: "https://api.example.com")!,
            session: makeSession(),
            cfAccessClientID: clientID,
            cfAccessClientSecret: clientSecret
        )
    }

    // MARK: - Headers present when configured

    @Test func libraryAttachesHeadersWhenConfigured() async throws {
        StubURLProtocol.responseBody = Data("[]".utf8)
        StubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        _ = try await repository.library()

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func saveProgressAttachesHeadersWhenConfigured() async throws {
        StubURLProtocol.responseBody = Data()
        StubURLProtocol.statusCode = 204

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 5)

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    // MARK: - Headers absent when unconfigured

    @Test func libraryOmitsHeadersWhenUnconfigured() async throws {
        StubURLProtocol.responseBody = Data("[]".utf8)
        StubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        _ = try await repository.library()

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func saveProgressOmitsHeadersWhenUnconfigured() async throws {
        StubURLProtocol.responseBody = Data()
        StubURLProtocol.statusCode = 204

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 5)

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func headersOmittedWhenOnlyOneCredentialIsPresent() async throws {
        StubURLProtocol.responseBody = Data("[]".utf8)
        StubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: nil)
        _ = try await repository.library()

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }
}
