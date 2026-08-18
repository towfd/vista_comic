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

    private let repository = APIComicRepository()

    /// Where downloaded chapters live (`offline-download` ticket 01). Falls back
    /// to an in-memory store if Application Support cannot be prepared: nothing
    /// is kept for that run, which is a better failure than refusing to launch.
    private let offlineChapterStore: any OfflineChapterStore
    /// Owned by the app rather than by a screen, because a download outlives the
    /// chapter list that started it — walking back to the library must not
    /// abandon it.
    @State private var downloads: ChapterDownloadManager

    init() {
        let store: any OfflineChapterStore =
            (try? FileOfflineChapterStore()) ?? InMemoryOfflineChapterStore()
        offlineChapterStore = store
        _downloads = State(
            initialValue: ChapterDownloadManager(store: store, repository: repository)
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
