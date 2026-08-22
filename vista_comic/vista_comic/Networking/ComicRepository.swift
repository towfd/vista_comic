//
//  ComicRepository.swift
//  vista_comic
//
//  The data-source seam introduced at M5 Slice 3. Screens depend on this
//  protocol, not on a concrete network client or on `SampleData`, so the app
//  can swap the live backend (`APIComicRepository`) for an in-memory mock
//  (`PreviewComicRepository`) in `#Preview`s and stay buildable offline.
//
//  API contract of record: `docs/api-contract.md`.
//

import SwiftUI

/// Fetches the comic library and its contents from a data source.
///
/// Mirrors the backend endpoints:
/// - `library()`            → `GET /comics`
/// - `comic(id:)`           → `GET /comics/{id}` (adds the chapter list)
/// - `readerChapter(comicID:chapterID:)` → `GET /comics/{id}/chapters/{cid}`
///   (page image URLs + resume position)
/// - `saveProgress(comicID:chapterID:lastPage:)` → `PUT /comics/{id}/chapters/{cid}/progress`
protocol ComicRepository {
    /// The whole library. Comics carry a `chapterCount` but no `chapters` yet.
    func library() async throws -> [Comic]

    /// One comic with its `chapters` populated (each chapter still has no pages).
    func comic(id: String) async throws -> Comic

    /// A single chapter fetched lazily when the reader opens it. Carries both the
    /// ordered `pageURLs` and the 1-based `lastReadPage` resume position (`nil`
    /// when there is no saved progress).
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter

    /// Rebuilds the backend's catalog from the library folder on disk.
    ///
    /// The catalog is scanned once at startup and held in memory — the folder
    /// stays the source of truth, and nothing watches it — so a comic or chapter
    /// added since then is invisible until something asks for a rescan. That
    /// "something" is the reader pulling to refresh; there is no other trigger
    /// short of restarting the backend.
    ///
    /// Rebuilds everything, so where it is called from does not matter: the
    /// library and the chapter list both reach the same catalog.
    func rescan() async throws

    /// Persist the reader's position for a chapter. `lastPage` is 1-based.
    /// Best-effort: callers should treat failures as non-fatal so reading is
    /// never interrupted when the progress store is unavailable.
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws
}

/// A screen's async fetch lifecycle: loading, loaded, or failed.
/// `Value` is deliberately not `Equatable` — views drive UI off the case, not
/// value equality.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(Error)
}

/// Where the app looks for the backend.
///
/// Values are baked into the compiled app at **build time** — via
/// `Config/Shared.xcconfig` (+ the gitignored `Config/Secrets.xcconfig`
/// override) flowing through `Info.plist` — rather than read from
/// `ProcessInfo.environment`. Scheme-level environment variables only exist
/// while Xcode launches the process; a build-time value survives launching
/// the app directly from the home screen with no debugger attached, which is
/// required once the base URL is the public tunnel hostname (`remote-access`).
///
/// The compiled fallback (`http://127.0.0.1:8000`) uses the explicit IPv4
/// loopback rather than `localhost`, which macOS resolves to IPv6 `::1`
/// first — anything else on `::1:8000` (e.g. a Docker port proxy) would
/// otherwise shadow the IPv4 uvicorn dev server.
enum APIConfig {
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "VistaBaseURL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }()

    /// Cloudflare Access Service Token credentials for the public tunnel
    /// hostname, set in the gitignored `Config/Secrets.xcconfig`. `nil` (no
    /// default) when unset, since local/simulator dev against `127.0.0.1`
    /// sits behind no Access policy and needs no credentials.
    static let cfAccessClientID: String? = nonEmptyInfoValue(forKey: "CFAccessClientID")

    static let cfAccessClientSecret: String? = nonEmptyInfoValue(forKey: "CFAccessClientSecret")

    private static func nonEmptyInfoValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// HTTP statuses that mean **the origin was never reached**, as opposed to
    /// reached and unhappy.
    ///
    /// A gateway answering 502/503/504 — or Cloudflare answering 530 — is
    /// telling the app there is nothing behind it. That is the same fact as a
    /// dropped connection, and the reader is equally unable to do anything
    /// about it, so it should degrade to whatever is cached rather than showing
    /// an error.
    ///
    /// **This exists because the tunnel makes "unreachable" arrive as a
    /// response.** Reproduced against the live tunnel: with the backend down it
    /// answers 502, and with `cloudflared` itself down it answers 530. Both are
    /// perfectly valid HTTP responses, so `URLSession` succeeds, no `URLError`
    /// is thrown, and a check for transport failure alone concludes the server
    /// answered — leaving a reader with a full cache on their phone staring at
    /// a connection error.
    ///
    /// Kept narrow on purpose. A 500 means the server is there and its code
    /// broke; a 401 or 403 means Access rejected the request. Both are live
    /// failures, and quietly serving yesterday's data for them would look
    /// perfectly normal on screen while being silently wrong.
    static let originUnreachableStatuses: Set<Int> = [502, 503, 504, 530]

    /// Whether `error` means nothing was reached, as opposed to reached and
    /// unhappy.
    ///
    /// The one place this question is answered, so the catalog, the deck and
    /// the practice round cannot drift apart about what "offline" means.
    static func isOriginUnreachable(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if case APIError.httpStatus(let code) = error {
            return originUnreachableStatuses.contains(code)
        }
        return false
    }

    /// Builds a request for an arbitrary absolute URL, attaching the
    /// Cloudflare Access Service Token headers when both credentials are
    /// present. Shared by `APIComicRepository` (JSON endpoints) and
    /// `AuthorizedAsyncImage` (media bytes) so every backend request
    /// authenticates the same way — `AsyncImage(url:)` has no API for custom
    /// headers, which is what let image loads slip through unauthenticated
    /// after Access was added in front of the tunnel.
    ///
    /// Takes credentials as parameters rather than reading `cfAccessClientID`/
    /// `cfAccessClientSecret` directly, so callers can inject test values
    /// without touching process-wide state.
    static func authorizedRequest(
        url: URL,
        method: String = "GET",
        clientID: String?,
        clientSecret: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let clientID, let clientSecret {
            request.setValue(clientID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        return request
    }

    /// A decoder for the backend's ISO-8601 timestamps. The backend emits
    /// them via Python's `datetime.isoformat()` (see `progress_store.iso_utc`),
    /// which includes fractional (microsecond) seconds whenever they're
    /// non-zero — e.g. `2026-07-29T22:20:10.081902+00:00`. `JSONDecoder`'s
    /// stock `.iso8601` strategy uses an `ISO8601DateFormatter` that does
    /// NOT accept fractional seconds and throws on that shape, so every
    /// timestamp field (`Comic.lastReadAt`, `ComprehensionRecord.createdAt`, ...)
    /// silently failed to decode as soon as real (not exactly-on-the-second)
    /// data existed — the whole response then failed with a generic
    /// "Couldn't connect" (`ErrorStateView` doesn't distinguish a decoding
    /// failure from a network one). Tries the fractional-seconds format
    /// first, then falls back to the plain format, so both shapes decode.
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { fieldDecoder in
            let container = try fieldDecoder.singleValueContainer()
            let string = try container.decode(String.self)

            let withFractionalSeconds = ISO8601DateFormatter()
            withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractionalSeconds.date(from: string) {
                return date
            }

            let withoutFractionalSeconds = ISO8601DateFormatter()
            withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
            if let date = withoutFractionalSeconds.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date string, got \"\(string)\""
            )
        }
        return decoder
    }
}

// MARK: - Environment injection

private struct ComicRepositoryKey: EnvironmentKey {
    /// Offline-safe default so `#Preview`s and the canvas never hit the network.
    static let defaultValue: any ComicRepository = PreviewComicRepository()
}

extension EnvironmentValues {
    /// The repository the current view tree reads its comics from.
    var comicRepository: any ComicRepository {
        get { self[ComicRepositoryKey.self] }
        set { self[ComicRepositoryKey.self] = newValue }
    }
}
