//
//  ComicView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/12.
//
//  Vertical reader. Chapters arrive without their pages (the `/comics/{id}`
//  summary), so the reader fetches each chapter's ordered page URLs lazily from
//  `/comics/{id}/chapters/{cid}` when it opens or when the chapter changes, and
//  renders them with `AsyncImage` (loading → placeholder, failure → placeholder).
//
import SwiftUI

struct ComicView: View{
    let comic: Comic
    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var showChapterList = false
    @State private var pagesState: LoadState<[URL]> = .loading
    @Environment(\.comicRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    /// How far the reader must be pulled *past* the bottom (points of overscroll)
    /// before advancing to the next chapter.
    private let pullThreshold: CGFloat = 120

    init(comic: Comic, chapter: Chapter) {
        self.comic = comic
        _currentChapter = State(initialValue: chapter)
    }

    var body: some View{
        ZStack{
            pagesContent

            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        // Use custom, immersive controls instead of the system navigation bar,
        // so there is no duplicate back button.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showChapterList) {
            chapterListSheet
        }
        // Load the current chapter's pages on open, and reload whenever the
        // chapter changes (prev / next / chapter list / auto-advance).
        .task(id: currentChapter.id) { await loadPages() }
    }

    // MARK: - Pages

    @ViewBuilder
    private var pagesContent: some View {
        switch pagesState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let urls):
            pagesScrollView(urls: urls)
        case .failed:
            ErrorStateView { Task { await loadPages() } }
        }
    }

    private func pagesScrollView(urls: [URL]) -> some View {
        ScrollView{
            // Lazy so a long chapter (~100+ pages) doesn't kick off every
            // `AsyncImage` at once; pages load as they scroll into view.
            LazyVStack(spacing: 0){
                // Renders the current chapter's pages as a continuous vertical read.
                ForEach(Array(urls.enumerated()), id: \.offset){ _, url in
                    ReaderPage(url: url)
                }
            }
        }
        // Auto-advance: after reaching the bottom, the user must keep pulling
        // *past* the end (overscroll) to continue into the next chapter — so
        // simply reaching the bottom is not enough. Does nothing on the last
        // chapter (nextChapter == nil), and only for content taller than the
        // screen (otherwise there is no bottom to pull past).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let maxScroll = geometry.contentSize.height - geometry.containerSize.height
            guard maxScroll > 0 else { return false }
            return geometry.contentOffset.y >= maxScroll + pullThreshold
        } action: { wasPulledPastEnd, isPulledPastEnd in
            if isPulledPastEnd && !wasPulledPastEnd {
                goTo(nextChapter)
            }
        }
        // Rebuild the scroll view when the chapter changes so a newly opened
        // chapter always starts at its first page instead of inheriting the
        // previous chapter's scroll offset.
        .id(currentChapter.id)
        .onTapGesture {
            withAnimation { showControls.toggle() }
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0){
            HStack(spacing: 17){
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
                Spacer()
                Button { showChapterList = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Chapter list")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)

            Spacer()

            HStack{
                Button { goTo(previousChapter) } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(previousChapter == nil)
                .accessibilityLabel("Previous chapter")

                Spacer()

                Text(currentChapter.title)
                    .font(AppFont.rowTitle)

                Spacer()

                Button { goTo(nextChapter) } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(nextChapter == nil)
                .accessibilityLabel("Next chapter")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        }
    }

    private var chapterListSheet: some View {
        NavigationStack {
            List(comic.chapters) { chapter in
                Button {
                    currentChapter = chapter
                    showChapterList = false
                } label: {
                    HStack{
                        Text(chapter.title)
                        Spacer()
                        if chapter.id == currentChapter.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primaryRed)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(comic.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Chapter navigation

    private var currentIndex: Int {
        comic.chapters.firstIndex { $0.id == currentChapter.id } ?? 0
    }

    private var previousChapter: Chapter? {
        currentIndex > 0 ? comic.chapters[currentIndex - 1] : nil
    }

    private var nextChapter: Chapter? {
        currentIndex < comic.chapters.count - 1 ? comic.chapters[currentIndex + 1] : nil
    }

    private func goTo(_ chapter: Chapter?) {
        guard let chapter else { return }
        currentChapter = chapter
    }

    // MARK: - Loading

    private func loadPages() async {
        pagesState = .loading
        do {
            let urls = try await repository.pageURLs(
                comicID: comic.id,
                chapterID: currentChapter.id
            )
            pagesState = .loaded(urls)
        } catch {
            pagesState = .failed(error)
        }
    }
}

/// A single reading page. `AsyncImage` provides the real loading state deferred
/// in M3. Because `AsyncImage` has no built-in retry, a failed page would stay
/// failed forever, so the failure placeholder is tappable: tapping bumps
/// `reloadToken`, which re-keys the `AsyncImage` so it re-issues the request.
private struct ReaderPage: View {
    let url: URL
    @State private var reloadToken = 0

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            case .failure:
                failurePlaceholder
            @unknown default:
                failurePlaceholder
            }
        }
        // Re-issue the request when the retry token changes.
        .id(reloadToken)
    }

    private var failurePlaceholder: some View {
        Button {
            reloadToken += 1
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.largeTitle)
                Text("Couldn't load this page")
                    .font(AppFont.caption)
                Text("Tap to retry")
                    .font(AppFont.caption)
            }
            .foregroundStyle(.grayFont)
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap to retry")
    }
}

#Preview("Reader") {
    NavigationStack {
        ComicView(comic: SampleData.comics[0], chapter: SampleData.comics[0].chapters[1])
    }
}

#Preview("Reader — pages failed") {
    NavigationStack {
        ComicView(comic: SampleData.comics[0], chapter: SampleData.comics[0].chapters[0])
            .environment(\.comicRepository, FailingPreviewRepository())
    }
}
