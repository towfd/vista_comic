//
//  APIComicRepository.swift
//  vista_comic
//
//  Live `ComicRepository` backed by the local FastAPI service over `URLSession`
//  with `Codable` decoding. See `docs/api-contract.md` for the contract.
//

import Foundation

/// Fetches comics from the backend JSON API.
struct APIComicRepository: ComicRepository {
    private let baseURL: URL
    private let session: URLSession
    private let cfAccessClientID: String?
    private let cfAccessClientSecret: String?
    /// Where a successful catalog response's bytes are kept so the library can
    /// still be rendered with no connection (`offline-download` ticket 02).
    ///
    /// It lives here, rather than in the decorator that reads it back, for the
    /// only reason that matters: **a decorator never sees the bytes.** It is
    /// handed decoded `Comic` values, and the display models are `Decodable`
    /// only — so storing from out there would mean making them `Encodable` and
    /// keeping a second representation of every field in step with the first.
    private let snapshots: (any CatalogSnapshotStore)?

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        cfAccessClientID: String? = APIConfig.cfAccessClientID,
        cfAccessClientSecret: String? = APIConfig.cfAccessClientSecret,
        snapshots: (any CatalogSnapshotStore)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cfAccessClientID = cfAccessClientID
        self.cfAccessClientSecret = cfAccessClientSecret
        self.snapshots = snapshots
    }

    /// Shared decoder: the backend emits ISO-8601 dates (e.g. `lastReadAt`).
    /// See `APIConfig.iso8601Decoder`'s doc comment for why this isn't the
    /// stock `.iso8601` strategy.
    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    func library() async throws -> [Comic] {
        try await get([Comic].self, at: "comics", snapshot: .library)
    }

    func comic(id: String) async throws -> Comic {
        try await get(Comic.self, at: "comics/\(id)", snapshot: .comic(id: id))
    }

    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        // The reader endpoint returns a chapter object whose `pages` are the URLs
        // and whose `lastReadPage` is the resume position.
        try await get(
            Chapter.self,
            at: "comics/\(comicID)/chapters/\(chapterID)"
        )
    }

    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["lastPage": lastPage])
        try await put(body: body, at: "comics/\(comicID)/chapters/\(chapterID)/progress")
    }

    func rescan() async throws {
        // The response reports how many comics and chapters were found; the
        // caller re-fetches the library either way, so the counts are the
        // backend's own log rather than something to decode here.
        try await post(at: "rescan")
    }

    // MARK: - Request plumbing

    /// Builds a `URLRequest` for `path`, routed through `APIConfig.authorizedRequest`
    /// so it attaches the Cloudflare Access Service Token headers exactly the
    /// way `AuthorizedAsyncImage` does for media bytes. This is the single
    /// construction point both `get` and `put` route through, so on-device
    /// requests through the public tunnel carry the headers while
    /// local/simulator requests against `127.0.0.1` (no credentials
    /// configured) are unaffected.
    private func makeRequest(method: String, at path: String) -> URLRequest {
        APIConfig.authorizedRequest(
            url: baseURL.appendingPathComponent(path),
            method: method,
            clientID: cfAccessClientID,
            clientSecret: cfAccessClientSecret
        )
    }

    /// - Parameter snapshot: when given, the response's bytes are kept under
    ///   this key so the same request can be answered from storage while the
    ///   network is unreachable. Only requests that are worth replaying offline
    ///   pass one — the reader endpoint deliberately does not, since a
    ///   downloaded chapter's record already answers it and a stored response
    ///   for a chapter with no pages on the device would answer it *wrongly*.
    private func get<T: Decodable>(
        _ type: T.Type,
        at path: String,
        snapshot: CatalogSnapshot? = nil
    ) async throws -> T {
        let request = makeRequest(method: "GET", at: path)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }

        let value: T
        do {
            value = try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }

        // Stored only after it decodes, so what is replayed offline is known to
        // be readable rather than merely known to have arrived.
        if let snapshot {
            snapshots?.store(data, for: snapshot)
        }
        return value
    }

    /// Sends a bodyless `POST` and treats any non-2xx status as an error.
    /// The response body is ignored, the same as `put` below.
    private func post(at path: String) async throws {
        let request = makeRequest(method: "POST", at: path)
        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }

    /// Sends a JSON body with `PUT` and treats any non-2xx status as an error.
    /// The response body is ignored; callers only care whether the write stuck.
    private func put(body: Data, at path: String) async throws {
        var request = makeRequest(method: "PUT", at: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }
}

/// Failures the repository surfaces to the UI, which shows the shared error view.
enum APIError: Error {
    case invalidResponse
    case httpStatus(Int)
    case decoding(any Error)
}
