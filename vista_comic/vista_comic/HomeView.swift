//
//  HomeView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//
//  The library's data-source seam (M5 Slice 3): drives `FavouriteView` from the
//  injected `ComicRepository` instead of `SampleData`, and owns the library's
//  loading / loaded / failure states. `FavouriteView` still owns the empty state.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.comicRepository) private var repository
    @State private var state: LoadState<[Comic]> = .loading
    /// Drives a silent refresh when the user pops back into the library.
    @State private var path = NavigationPath()
    /// First load shows the full-screen spinner; later refreshes are silent.
    @State private var hasLoadedOnce = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Comic.self) { comic in
                    ChapterPageView(comic: comic)
                }
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(
                        comicID: route.comicID,
                        chapterID: route.chapterID,
                        targetPage: route.targetPage,
                        isPeek: route.isPeek
                    )
                }
        }
        .task { await load() }
        // Returning from a pushed screen (chapter list / reader) shrinks the
        // path; re-fetch so "last read", the Continue target, and read badges
        // reflect progress saved while reading — without an app relaunch.
        .onChange(of: path) { oldPath, newPath in
            if newPath.count < oldPath.count {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let comics):
            FavouriteView(comics: comics)
        case .failed:
            ErrorStateView { Task { await load() } }
        }
    }

    private func load() async {
        // Only the first load shows the spinner; a refresh-on-return keeps the
        // current library visible and swaps in fresh data on success.
        if !hasLoadedOnce {
            state = .loading
        }
        do {
            state = .loaded(try await repository.library())
            hasLoadedOnce = true
        } catch {
            // A failed background refresh keeps the stale (but usable) library;
            // only a failed first load surfaces the error page.
            if !hasLoadedOnce {
                state = .failed(error)
            }
        }
    }
}

#Preview {
    HomeView()
}
