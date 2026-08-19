//
//  APIStudyRepository.swift
//  vista_comic
//
//  Live `StudyRepository` backed by the FastAPI service over `URLSession`,
//  mirroring `APIComprehensionRepository`'s request-building and decoding
//  conventions exactly — including Cloudflare Access header attachment through
//  `APIConfig.authorizedRequest`, so every request routes through one
//  construction point. See `backend/app/main.py`'s `/cards` handlers.
//

import Foundation

/// Collects and reads learning cards against the backend's `/cards` API.
struct APIStudyRepository: StudyRepository {
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

    /// Shared decoder: the backend emits ISO-8601 timestamps. See
    /// `APIConfig.iso8601Decoder` for why this isn't the stock `.iso8601`
    /// strategy. `dueOn` is a date rather than an instant and stays a `String`
    /// on the model, so it never reaches this.
    private var decoder: JSONDecoder { APIConfig.iso8601Decoder }

    private let resourcePath = "cards"

    @discardableResult
    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> LearningCard {
        let payload: [String: Any] = [
            "sourceText": sourceText,
            "translation": translation,
            "targetLanguage": targetLanguage,
            "comicId": comicID,
            "chapterId": chapterID,
            "pageNumber": pageNumber,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        // 200 and 201 are both success here: the backend answers 200 when the
        // line was already collected. `validate` accepts the whole 2xx range,
        // so nothing extra is needed to treat them alike — which is the point
        // of the backend having chosen 200 over 409.
        return try await send(LearningCard.self, method: "POST", at: resourcePath, body: body)
    }

    func cards() async throws -> [LearningCard] {
        try await send([LearningCard].self, method: "GET", at: resourcePath)
    }

    func recordLookup(id: Int) async throws {
        let request = makeRequest(method: "POST", at: "\(resourcePath)/\(id)/lookups")
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    // MARK: - Request plumbing

    private func makeRequest(method: String, at path: String) -> URLRequest {
        APIConfig.authorizedRequest(
            url: baseURL.appendingPathComponent(path),
            method: method,
            clientID: cfAccessClientID,
            clientSecret: cfAccessClientSecret
        )
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }

    private func send<T: Decodable>(
        _ type: T.Type,
        method: String,
        at path: String,
        body: Data? = nil
    ) async throws -> T {
        var request = makeRequest(method: method, at: path)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
