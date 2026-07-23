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

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Comic.self) { comic in
                    ChapterPageView(comic: comic)
                }
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(comicID: route.comicID, chapterID: route.chapterID)
                }
        }
        .task { await load() }
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
        state = .loading
        do {
            state = .loaded(try await repository.library())
        } catch {
            state = .failed(error)
        }
    }
}

#Preview {
    HomeView()
}
