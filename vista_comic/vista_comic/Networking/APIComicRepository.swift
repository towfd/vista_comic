//
//  APIComicRepository.swift
//  vista_comic
//
//  Live `ComicRepository` backed by the local FastAPI service over `URLSession`
//  with `Codable` decoding. See `docs/backend-architecture.md` for the contract.
//

import Foundation

/// Fetches comics from the backend JSON API.
struct APIComicRepository: ComicRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Shared decoder: the backend emits ISO-8601 dates (e.g. `lastReadAt`).
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func library() async throws -> [Comic] {
        try await get([Comic].self, at: "comics")
    }

    func comic(id: String) async throws -> Comic {
        try await get(Comic.self, at: "comics/\(id)")
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

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ type: T.Type, at path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)

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

    /// Sends a JSON body with `PUT` and treats any non-2xx status as an error.
    /// The response body is ignored; callers only care whether the write stuck.
    private func put(body: Data, at path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
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
