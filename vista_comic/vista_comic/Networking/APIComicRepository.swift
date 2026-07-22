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

    func pageURLs(comicID: String, chapterID: String) async throws -> [URL] {
        // The reader endpoint returns a chapter object whose `pages` are the URLs.
        let chapter = try await get(
            Chapter.self,
            at: "comics/\(comicID)/chapters/\(chapterID)"
        )
        return chapter.pageURLs
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
}

/// Failures the repository surfaces to the UI, which shows the shared error view.
enum APIError: Error {
    case invalidResponse
    case httpStatus(Int)
    case decoding(any Error)
}
