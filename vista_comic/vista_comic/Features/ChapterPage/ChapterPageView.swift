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
    @Environment(\.chapterDownloads) private var downloads
    @State private var state: LoadState<Comic> = .loading
    /// First load shows the full-screen spinner; later refreshes are silent.
    @State private var hasLoadedOnce = false

    var body: some View {
        // The refusal at the cap is reported here rather than on the row that
        // caused it: one alert for the screen instead of one per chapter, and
        // ticket 04 removes it along with refusing.
        @Bindable var downloads = downloads

        return content
            .task { await load() }
            .alert("Download limit reached", isPresented: $downloads.limitAlertIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can keep \(OfflineDownloadLimits.maxChapters) chapters on your device.")
            }
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
                .refreshable { await rescanAndLoad() }
        case .failed:
            ErrorStateView { Task { await load() } }
        }
    }

    /// Same gesture as the library's, and for the more common reason: chapters
    /// arrive in a comic that is already on the shelf. A rescan rebuilds the
    /// whole catalog, so pulling here is exactly as effective as walking back to
    /// the library to do it — and this is where the reader already is.
    private func rescanAndLoad() async {
        try? await repository.rescan()
        await load()
    }

    private func loaded(_ detail: Comic) -> some View {
        VStack {
            CoverImage(url: detail.coverURL)
                .frame(width: 187, height: 187)
            Text(detail.title)
                .font(AppFont.title)

            ScrollView {
                // Lazy now that each row loads its own cover: a comic with a
                // hundred chapters would otherwise request a hundred
                // full-resolution pages the moment the list appears.
                LazyVStack(spacing: 0) {
                    ForEach(detail.chapters) { chapter in
                        ChapterListView(comic: detail, chapter: chapter)
                    }
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
