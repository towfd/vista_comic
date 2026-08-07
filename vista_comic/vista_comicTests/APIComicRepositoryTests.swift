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
///
/// File-private and not shared with `AuthorizedAsyncImageTests` on purpose:
/// an earlier version extracted this into a common file, but its static
/// `lastRequest`/`responseBody`/`statusCode` state is global, and Swift
/// Testing may run different `@Suite`s in parallel with each other even
/// though `.serialized` keeps tests *within* one suite sequential — the two
/// suites raced and corrupted each other's stubbed state. A dedicated class
/// per suite has its own static storage, so there's nothing to race.
private final class RepositoryStubURLProtocol: URLProtocol {
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
        RepositoryStubURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: RepositoryStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: RepositoryStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("APIComicRepository Cloudflare Access headers", .serialized)
struct APIComicRepositoryTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RepositoryStubURLProtocol.self]
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

    // MARK: - Chapter covers

    /// A chapter carries whichever cover the server resolved for it — its own
    /// `cover.*` where it has one, the comic's otherwise. This asserts the
    /// decoding, not that rule; the rule is the backend's and is tested there.
    @Test func comicDetailDecodesEachChaptersOwnCover() async throws {
        RepositoryStubURLProtocol.responseBody = Data("""
        {
            "id": "comic-1",
            "title": "Alpha",
            "coverUrl": "https://example.test/media/comic-1/cover",
            "chapters": [
                {
                    "id": "ch-1", "number": 1, "title": "One", "pageCount": 2,
                    "readState": "unread",
                    "coverUrl": "https://example.test/media/comic-1/ch-1/cover"
                },
                {
                    "id": "ch-2", "number": 2, "title": "Two", "pageCount": 3,
                    "readState": "unread",
                    "coverUrl": "https://example.test/media/comic-1/ch-2/cover"
                }
            ]
        }
        """.utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let comic = try await makeRepository(clientID: nil, clientSecret: nil).comic(id: "comic-1")

        #expect(comic.chapters.count == 2)
        #expect(
            comic.chapters[0].coverURL
                == URL(string: "https://example.test/media/comic-1/ch-1/cover")
        )
        // Decoded per chapter rather than shared or dropped.
        #expect(comic.chapters[1].coverURL == URL(string: "https://example.test/media/comic-1/ch-2/cover"))
    }

    /// The reader endpoint returns the full page list and no separate cover,
    /// where one would just be the first of those pages repeated. Decoding must
    /// not require it.
    @Test func aChapterWithoutACoverStillDecodes() async throws {
        RepositoryStubURLProtocol.responseBody = Data("""
        {
            "id": "ch-1", "number": 1, "title": "One", "pageCount": 1,
            "readState": "unread",
            "pages": ["https://example.test/media/comic-1/ch-1/1"]
        }
        """.utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let chapter = try await makeRepository(clientID: nil, clientSecret: nil)
            .readerChapter(comicID: "comic-1", chapterID: "ch-1")

        #expect(chapter.coverURL == nil)
        #expect(chapter.pageURLs.count == 1)
    }

    // MARK: - Headers present when configured

    @Test func libraryAttachesHeadersWhenConfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data("[]".utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        _ = try await repository.library()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func saveProgressAttachesHeadersWhenConfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data()
        RepositoryStubURLProtocol.statusCode = 204

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 5)

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    // MARK: - Rescan

    /// The catalog is scanned once at startup and held in memory, so this is
    /// the only way a comic added since then becomes visible without restarting
    /// the backend. It must be a `POST` to `/rescan` and nothing else.
    @Test func rescanPostsToTheRescanPath() async throws {
        RepositoryStubURLProtocol.responseBody = Data(
            #"{"status":"rescanned","comics":3,"chapters":9}"#.utf8
        )
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        try await repository.rescan()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rescan")
        // Nothing to send: the backend rescans the folder it already knows about.
        #expect(request.httpBody == nil)
    }

    @Test func rescanAttachesHeadersWhenConfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data("{}".utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: "test-client-secret")
        try await repository.rescan()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-client-secret")
    }

    @Test func rescanOmitsHeadersWhenUnconfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data("{}".utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        try await repository.rescan()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    /// Surfaced rather than swallowed, so the pull gesture's caller can decide
    /// what to do about it. Both screens choose to reload anyway — a failed
    /// rescan should still show the reader whatever the backend already has.
    @Test func rescanThrowsHTTPStatusErrorOnServerFailure() async throws {
        RepositoryStubURLProtocol.responseBody = Data()
        RepositoryStubURLProtocol.statusCode = 503

        let repository = makeRepository(clientID: nil, clientSecret: nil)

        await #expect(throws: APIError.self) {
            try await repository.rescan()
        }
    }

    // MARK: - Headers absent when unconfigured

    @Test func libraryOmitsHeadersWhenUnconfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data("[]".utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        _ = try await repository.library()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func saveProgressOmitsHeadersWhenUnconfigured() async throws {
        RepositoryStubURLProtocol.responseBody = Data()
        RepositoryStubURLProtocol.statusCode = 204

        let repository = makeRepository(clientID: nil, clientSecret: nil)
        try await repository.saveProgress(comicID: "comic-1", chapterID: "chapter-1", lastPage: 5)

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }

    @Test func headersOmittedWhenOnlyOneCredentialIsPresent() async throws {
        RepositoryStubURLProtocol.responseBody = Data("[]".utf8)
        RepositoryStubURLProtocol.statusCode = 200

        let repository = makeRepository(clientID: "test-client-id", clientSecret: nil)
        _ = try await repository.library()

        let request = try #require(RepositoryStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
    }
}
