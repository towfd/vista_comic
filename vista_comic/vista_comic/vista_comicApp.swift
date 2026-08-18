//
//  vista_comicApp.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//

import SwiftUI

@main
struct vista_comicApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// The live backend, wrapped in the offline fallback (ticket 02). Every
    /// screen keeps depending on `ComicRepository` and none of them knows the
    /// difference — which is the point of doing it as a decorator.
    private let repository: any ComicRepository

    /// Where downloaded chapters live (`offline-download` ticket 01). Falls back
    /// to an in-memory store if Application Support cannot be prepared: nothing
    /// is kept for that run, which is a better failure than refusing to launch.
    private let offlineChapterStore: any OfflineChapterStore

    /// The app's own image cache, identical to `MemoryPageImageCache.shared`
    /// except that it knows where downloaded pages live, so the disk is
    /// consulted before the network for every image the app loads. Created once
    /// here and alive for the whole process, exactly as the singleton was.
    private let pageImageCache: MemoryPageImageCache
    /// Owned by the app rather than by a screen, because a download outlives the
    /// chapter list that started it — walking back to the library must not
    /// abandon it.
    @State private var downloads: ChapterDownloadManager

    init() {
        let chapters: any OfflineChapterStore =
            (try? FileOfflineChapterStore()) ?? InMemoryOfflineChapterStore()
        // Same fallback reasoning: with nowhere to keep them, the library simply
        // needs a connection, as it always has.
        let snapshots: any CatalogSnapshotStore =
            (try? FileCatalogSnapshotStore()) ?? InMemoryCatalogSnapshotStore()

        let repository = OfflineFallbackComicRepository(
            // The inner repository is the one that stores snapshots, because it
            // is the only thing that ever sees the raw response bytes.
            wrapping: APIComicRepository(snapshots: snapshots),
            snapshots: snapshots,
            chapters: chapters
        )

        self.offlineChapterStore = chapters
        self.repository = repository
        self.pageImageCache = MemoryPageImageCache(offlineChapters: chapters)
        _downloads = State(
            initialValue: ChapterDownloadManager(store: chapters, repository: repository)
        )
    }

    var body: some Scene {
        WindowGroup {
            // Inject the live backend repository. Previews and the canvas fall
            // back to `PreviewComicRepository` via the environment default.
            // RootTabView hosts the tab bar; HomeView (書庫) is nested one
            // level deeper but still depends on this environment value.
            RootTabView()
                .environment(\.comicRepository, repository)
                .environment(\.pageImageCache, pageImageCache)
                .environment(\.offlineChapterStore, offlineChapterStore)
                .environment(\.chapterDownloads, downloads)
        }
        // Downloading is foreground-only: the app going to the background pauses
        // the chapter in flight, keeping its pages and its place in the queue,
        // and returning resumes it. Only `.background` counts — `.inactive` is
        // also a notification shade or the app switcher, and pausing for those
        // would stop a download the reader never left.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: downloads.pause()
            case .active: downloads.resume()
            default: break
            }
        }
    }
}
