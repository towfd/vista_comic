//
//  APITranslationRepository.swift
//  vista_comic
//
//  Live `TranslationRepository` backed by the local FastAPI service over
//  `URLSession` with `Codable` decoding, mirroring `APIComicRepository`'s
//  request-building/decoding conventions exactly (including Cloudflare
//  Access header attachment via `APIConfig.authorizedRequest`). See
//  `backend/app/main.py`'s `save_translation`/`list_translations` handlers
//  for the endpoints this calls.
//

import Foundation

/// Saves and lists translations against the backend's `/translations` API.
struct APITranslationRepository: TranslationRepository {
    private let baseURL: URL
    private let session: URLSession
    private let cfAccessClientID: String?
    private let cfAccessClientSecret: String?

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        cfAccessClientID: String? = APIConfig.cfAccessClientID,
        cfAccessClientSecret: String? = APIConfig.cfAccessClientSecret
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cfAccessClientID = cfAccessClientID
        self.cfAccessClientSecret = cfAccessClientSecret
    }

    /// Shared decoder: the backend emits ISO-8601 dates (`savedAt`). See
    /// `APIConfig.iso8601Decoder`'s doc comment for why this isn't the stock
    /// `.iso8601` strategy.
    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    @discardableResult
    func save(
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> SavedTranslation {
        let body = try JSONSerialization.data(withJSONObject: [
            "originalText": originalText,
            "translatedText": translatedText,
            "targetLanguage": targetLanguage,
            "comicId": comicID,
            "chapterId": chapterID,
            "pageNumber": pageNumber,
        ])
        return try await post(SavedTranslation.self, body: body, at: "translations")
    }

    func list() async throws -> [SavedTranslation] {
        try await get([SavedTranslation].self, at: "translations")
    }

    func delete(id: Int) async throws {
        try await delete(at: "translations/\(id)")
    }

    // MARK: - Request plumbing

    /// Builds a `URLRequest` for `path`, routed through `APIConfig.authorizedRequest`
    /// so it attaches the Cloudflare Access Service Token headers exactly the
    /// way `APIComicRepository` does. Every request — `get` and `post` alike —
    /// routes through this single construction point.
    private func makeRequest(method: String, at path: String) -> URLRequest {
        APIConfig.authorizedRequest(
            url: baseURL.appendingPathComponent(path),
            method: method,
            clientID: cfAccessClientID,
            clientSecret: cfAccessClientSecret
        )
    }

    private func get<T: Decodable>(_ type: T.Type, at path: String) async throws -> T {
        let request = makeRequest(method: "GET", at: path)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Sends a JSON body with `POST` and decodes the response as `T` — unlike
    /// `APIComicRepository.put`, whose response body is ignored, `save`'s
    /// caller needs the echoed record (its server-generated `id`/`savedAt`).
    private func post<T: Decodable>(_ type: T.Type, body: Data, at path: String) async throws -> T {
        var request = makeRequest(method: "POST", at: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Sends `DELETE` and treats any non-2xx status as an error. The
    /// response body is ignored (the backend returns 204 with none) —
    /// mirrors `APIComicRepository.put`'s ignored-body shape.
    private func delete(at path: String) async throws {
        let request = makeRequest(method: "DELETE", at: path)
        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }
}
