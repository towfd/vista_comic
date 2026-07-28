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
