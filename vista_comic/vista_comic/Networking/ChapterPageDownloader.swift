//
//  ChapterPageDownloader.swift
//  vista_comic
//
//  The bytes half of `offline-download` ticket 01: fetching a chapter's pages
//  and handing them to `OfflineChapterStore`. Separate from
//  `ChapterDownloadManager`, which owns queueing, state and the app lifecycle,
//  so that "what does downloading a chapter cost the network?" can be tested
//  without a view, a queue, or a lifecycle.
//
//  Deliberately **not** a protocol. A test substitutes the store and stubs
//  `URLProtocol` — a third seam here would buy nothing those two do not already
//  give, and would add an indirection with no second implementation behind it.
//

import Foundation

/// Fetches a chapter's pages, four at a time, skipping whatever is already on
/// disk.
struct ChapterPageDownloader: Sendable {
    /// At most four fetches run at once — the same number, for the same reason,
    /// as `FetchCoordinator`'s in-flight limit: at ~100 KB a page, a fetch costs
    /// round-trip latency rather than bandwidth, so four hides the latency
    /// without saturating the connection the reader may still be reading over.
    static let maxConcurrentPageFetches = 4

    let store: any OfflineChapterStore
    let session: URLSession
    let clientID: String?
    let clientSecret: String?

    init(
        store: any OfflineChapterStore,
        session: URLSession = .shared,
        clientID: String? = APIConfig.cfAccessClientID,
        clientSecret: String? = APIConfig.cfAccessClientSecret
    ) {
        self.store = store
        self.session = session
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Downloads every page of `chapterID` that is not already on disk.
    ///
    /// `onPagesStored` reports how many of `pageURLs` are present in total, not
    /// how many this call fetched — a resumed chapter therefore reports the
    /// progress it already had rather than restarting the ring from zero.
    ///
    /// Returns normally only when every page is present. Cancelling the calling
    /// task stops the work promptly and leaves whatever had arrived on disk;
    /// deciding whether that partial chapter is kept (paused) or discarded
    /// (cancelled) belongs to the caller, which is the only thing that knows
    /// which of the two happened.
    func download(
        pageURLs: [URL],
        of chapterID: DownloadedChapterID,
        onPagesStored: @escaping @Sendable (Int) -> Void
    ) async throws {
        let missing = pageURLs.filter { !store.hasPage($0, of: chapterID) }
        var stored = pageURLs.count - missing.count
        onPagesStored(stored)
        guard !missing.isEmpty else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            // The window is filled up front rather than by adding every task and
            // hoping the runtime limits them: a task group runs everything it is
            // given at once, so the limit has to be the number of tasks alive.
            while next < min(Self.maxConcurrentPageFetches, missing.count) {
                let url = missing[next]
                group.addTask { try await fetchAndStore(url, of: chapterID) }
                next += 1
            }

            while try await group.next() != nil {
                stored += 1
                onPagesStored(stored)
                guard next < missing.count else { continue }
                let url = missing[next]
                next += 1
                group.addTask { try await fetchAndStore(url, of: chapterID) }
            }
        }
    }

    /// One page: fetched through the same authorized-request path as every other
    /// backend call, so Cloudflare Access headers are attached exactly the way
    /// they are for JSON and for images.
    ///
    /// Stores the response bytes as they arrived. Nothing is decoded here — a
    /// download must not pay for 60–180 full-resolution decodes, and the memory
    /// cache decodes a page when it is actually about to be shown.
    private func fetchAndStore(_ url: URL, of chapterID: DownloadedChapterID) async throws {
        let request = APIConfig.authorizedRequest(
            url: url,
            clientID: clientID,
            clientSecret: clientSecret
        )
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        // Checked after the response and before the write, so a cancelled
        // download cannot leave a page on disk that its progress never counted.
        try Task.checkCancellation()
        try store.writePage(data, for: url, of: chapterID)
    }
}
