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
    /// Where the last good `GET /cards` response is kept. This repository is
    /// the only thing that ever sees the raw bytes, which is why it owns the
    /// snapshot — the same asymmetry `APIComicRepository` has with
    /// `CatalogSnapshotStore`.
    private let snapshots: any DeckSnapshotStore

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        cfAccessClientID: String? = APIConfig.cfAccessClientID,
        cfAccessClientSecret: String? = APIConfig.cfAccessClientSecret,
        snapshots: (any DeckSnapshotStore)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cfAccessClientID = cfAccessClientID
        self.cfAccessClientSecret = cfAccessClientSecret
        // The app's usual shape for a disk-backed store: with nowhere to keep
        // it, the feature degrades rather than fails.
        self.snapshots = snapshots
            ?? (try? FileDeckSnapshotStore())
            ?? InMemoryDeckSnapshotStore()
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
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome {
        var payload: [String: Any] = [
            "sourceText": sourceText,
            "translation": translation,
            "targetLanguage": targetLanguage,
            "comicId": comicID,
            "chapterId": chapterID,
            "pageNumber": pageNumber,
        ]
        // Omitted rather than sent as null when unanswered, so the field is
        // absent for a client that has nothing to say about it.
        if let kind { payload["kind"] = kind.rawValue }
        let body = try JSONSerialization.data(withJSONObject: payload)
        // 200 and 201 are both success here: the backend answers 200 when the
        // line was already collected. `validate` accepts the whole 2xx range,
        // so nothing extra is needed to treat them alike — which is the point
        // of the backend having chosen 200 over 409.
        let card = try await send(
            LearningCard.self, method: "POST", at: resourcePath, body: body
        )
        // Refresh the snapshot so the word just collected is recognised the
        // next time it is selected, in this same session.
        //
        // Awaited rather than fired off in the background: the add already
        // costs a round trip, a second one is cheap beside it, and a detached
        // task would make "is the snapshot current?" depend on timing. It is
        // deliberately best-effort — a failed refresh must never turn a
        // successful add into a failure the reader sees.
        _ = try? await cards()
        return .collected(card)
    }

    func cards() async throws -> [LearningCard] {
        let request = makeRequest(method: "GET", at: resourcePath)
        let (data, response) = try await session.data(for: request)
        try validate(response)

        let decoded: [LearningCard]
        do {
            decoded = try decoder.decode([LearningCard].self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
        // Stored only after it decoded: bytes that this build cannot read are
        // worse than no snapshot, because they would be replayed on every
        // launch and fail every time.
        snapshots.store(data)
        return decoded
    }

    func knownCards() -> [LearningCard] {
        guard let data = snapshots.data() else { return [] }
        return (try? decoder.decode([LearningCard].self, from: data)) ?? []
    }

    @discardableResult
    func update(
        id: Int,
        translation: String,
        kind: CardKind?
    ) async throws -> LearningCard {
        // `kind` is sent explicitly as null when unanswered, unlike `collect`
        // where it is omitted. The two cases genuinely differ: omitting it on a
        // create means "nothing to say", while omitting it here would mean
        // "leave it alone" — and clearing a classification has to be possible.
        let payload: [String: Any] = [
            "translation": translation,
            "kind": kind?.rawValue as Any? ?? NSNull(),
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let card = try await send(
            LearningCard.self, method: "PATCH", at: "\(resourcePath)/\(id)", body: body
        )
        // The snapshot the already-collected marker reads must not go on
        // showing a translation that has just been corrected.
        _ = try? await cards()
        return card
    }

    func delete(id: Int) async throws {
        let request = makeRequest(method: "DELETE", at: "\(resourcePath)/\(id)")
        let (_, response) = try await session.data(for: request)
        try validate(response)
        // Likewise: the marker must not go on answering from a card that no
        // longer exists.
        _ = try? await cards()
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
