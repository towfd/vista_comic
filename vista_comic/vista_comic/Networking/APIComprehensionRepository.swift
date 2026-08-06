//
//  APIComprehensionRepository.swift
//  vista_comic
//
//  Live `ComprehensionRepository` backed by the local FastAPI service over
//  `URLSession` with `Codable` decoding, mirroring `APITranslationRepository`'s
//  request-building/decoding conventions exactly — including Cloudflare Access
//  header attachment through `APIConfig.authorizedRequest`, so every request
//  routes through one construction point. See `backend/app/main.py`'s
//  `/comprehensions` handlers for the endpoints this calls.
//

import Foundation

/// Creates and manages comprehension records against the backend's
/// `/comprehensions` API.
struct APIComprehensionRepository: ComprehensionRepository {
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

    /// Shared decoder: the backend emits ISO-8601 dates (`createdAt`). See
    /// `APIConfig.iso8601Decoder`'s doc comment for why this isn't the stock
    /// `.iso8601` strategy.
    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    private let resourcePath = "comprehensions"

    @discardableResult
    func enqueue(
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        useStrongerModel: Bool
    ) async throws -> ComprehensionRecord {
        let payload: [String: Any] = [
            "sourceText": sourceText,
            "translatedText": translatedText,
            "targetLanguage": targetLanguage,
            "comicId": comicID,
            "chapterId": chapterID,
            "pageNumber": pageNumber,
            "useStrongerModel": useStrongerModel,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        // The only call that maps 429 to its own error: the daily cap is the
        // one enqueue failure the reader cannot fix by trying again, so the
        // screen must be able to say so instead of offering a pointless retry.
        return try await send(
            ComprehensionRecord.self,
            method: "POST",
            at: resourcePath,
            body: body,
            capAwareness: .distinguishDailyCap
        )
    }

    func list() async throws -> [ComprehensionRecord] {
        try await send([ComprehensionRecord].self, method: "GET", at: resourcePath)
    }

    func record(id: Int) async throws -> ComprehensionRecord {
        try await send(ComprehensionRecord.self, method: "GET", at: "\(resourcePath)/\(id)")
    }

    @discardableResult
    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        let body = try JSONSerialization.data(withJSONObject: ["isRead": isRead])
        return try await send(
            ComprehensionRecord.self, method: "PATCH", at: "\(resourcePath)/\(id)", body: body
        )
    }

    @discardableResult
    func retry(id: Int) async throws -> ComprehensionRecord {
        // Retrying costs another request against the daily cap, so it can be
        // refused for the same reason an enqueue can.
        try await send(
            ComprehensionRecord.self,
            method: "POST",
            at: "\(resourcePath)/\(id)/retry",
            capAwareness: .distinguishDailyCap
        )
    }

    func delete(id: Int) async throws {
        let request = makeRequest(method: "DELETE", at: "\(resourcePath)/\(id)")
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    // MARK: - Request plumbing

    /// Whether a 429 from this call should surface as
    /// `ComprehensionEnqueueError.dailyCapReached` rather than a generic HTTP
    /// status error. Only the two calls that *spend* a request can hit the cap.
    private enum CapAwareness {
        case generic
        case distinguishDailyCap
    }

    /// Builds a `URLRequest` for `path`, routed through
    /// `APIConfig.authorizedRequest` so it attaches the Cloudflare Access
    /// Service Token headers exactly the way `APIComicRepository` does. Every
    /// request routes through this single construction point.
    private func makeRequest(method: String, at path: String) -> URLRequest {
        APIConfig.authorizedRequest(
            url: baseURL.appendingPathComponent(path),
            method: method,
            clientID: cfAccessClientID,
            clientSecret: cfAccessClientSecret
        )
    }

    private func validate(
        _ response: URLResponse,
        capAwareness: CapAwareness = .generic
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 429, capAwareness == .distinguishDailyCap {
            throw ComprehensionEnqueueError.dailyCapReached
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }

    /// One send-and-decode for every call that returns a body, since the six
    /// routes differ only in method, path and whether they carry one.
    private func send<T: Decodable>(
        _ type: T.Type,
        method: String,
        at path: String,
        body: Data? = nil,
        capAwareness: CapAwareness = .generic
    ) async throws -> T {
        var request = makeRequest(method: method, at: path)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        try validate(response, capAwareness: capAwareness)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
