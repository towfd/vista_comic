//
//  ChapterPageView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//
//  Chapter list screen. The comic arriving from the library carries only a
//  `chapterCount` (the `/comics` summary), so this screen fetches the comic's
//  detail (`/comics/{id}`) to load its chapters, with loading and failure states.
//
import SwiftUI

struct ChapterPageView: View {
    let comic: Comic

    @Environment(\.comicRepository) private var repository
    @State private var state: LoadState<Comic> = .loading
    /// First load shows the full-screen spinner; later refreshes are silent.
    @State private var hasLoadedOnce = false

    var body: some View {
        content
            .task { await load() }
            // Re-fetch when this screen is revealed again after the reader is
            // popped, so per-chapter read badges reflect saved progress. Gated on
            // `hasLoadedOnce` so it doesn't double-load on first appearance.
            .onAppear {
                if hasLoadedOnce {
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
        case .loaded(let detail):
            loaded(detail)
        case .failed:
            ErrorStateView { Task { await load() } }
        }
    }

    private func loaded(_ detail: Comic) -> some View {
        VStack {
            CoverImage(url: detail.coverURL)
                .frame(width: 187, height: 187)
            Text(detail.title)
                .font(AppFont.title)

            ScrollView {
                ForEach(detail.chapters) { chapter in
                    ChapterListView(comic: detail, chapter: chapter)
                }
            }
        }
    }

    private func load() async {
        // Only the first load shows the spinner; a refresh-on-return keeps the
        // current chapter list visible and swaps in fresh data on success.
        if !hasLoadedOnce {
            state = .loading
        }
        do {
            state = .loaded(try await repository.comic(id: comic.id))
            hasLoadedOnce = true
        } catch {
            // A failed background refresh keeps the stale list; only a failed
            // first load surfaces the error page.
            if !hasLoadedOnce {
                state = .failed(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChapterPageView(comic: SampleData.comics[0])
            .navigationDestination(for: ReaderRoute.self) { route in
                ComicView(comicID: route.comicID, chapterID: route.chapterID)
            }
    }
}
