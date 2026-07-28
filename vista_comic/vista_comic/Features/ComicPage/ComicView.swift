//
//  ComicView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/12.
//
//  Vertical reader. Entered by id only (see `ReaderRoute`), because entry points
//  like the library card have no chapters loaded. `ComicView` fetches the comic
//  detail (`/comics/{id}`) to resolve the chapter list, then hands off to the
//  inner `ReaderView`, which fetches each chapter's ordered page URLs lazily from
//  `/comics/{id}/chapters/{cid}` when it opens or when the chapter changes, and
//  renders them with `AsyncImage` (loading → placeholder, failure → placeholder).
//
import SwiftUI

/// Ids-based entry to the reader. Loads the comic detail so the reader can offer
/// prev/next navigation and the chapter-list sheet even when the caller (e.g. the
/// library card) only knows the comic and chapter ids.
struct ComicView: View {
    let comicID: String
    let chapterID: String

    @Environment(\.comicRepository) private var repository
    @State private var comicState: LoadState<Comic> = .loading

    var body: some View {
        content
            .task { await loadComic() }
    }

    @ViewBuilder
    private var content: some View {
        switch comicState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let comic):
            // Resolve the requested chapter, falling back to the first one when
            // the id is unknown (e.g. an empty/best-effort Continue target).
            if let initial = comic.chapters.first(where: { $0.id == chapterID })
                ?? comic.chapters.first {
                ReaderView(comic: comic, initialChapter: initial)
            } else {
                // Detail with no chapters: nothing to read, offer a retry.
                ErrorStateView { Task { await loadComic() } }
            }
        case .failed:
            ErrorStateView { Task { await loadComic() } }
        }
    }

    private func loadComic() async {
        comicState = .loading
        do {
            comicState = .loaded(try await repository.comic(id: comicID))
        } catch {
            comicState = .failed(error)
        }
    }
}

/// The reader itself, now working from a fully-loaded comic and a starting chapter.
private struct ReaderView: View {
    let comic: Comic
    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var showChapterList = false
    @State private var pagesState: LoadState<[URL]> = .loading
    /// Resume anchor only: set on load to programmatically scroll to the resume
    /// page via `.scrollPosition`. The *set* direction is reliable; its reported
    /// value on a LazyVStack of unknown-height AsyncImages is not, so it is NOT
    /// used for progress reporting (see `visiblePages`).
    @State private var topPage: Int?
    /// 0-based indices of the pages currently on screen, maintained by each
    /// `ReaderPage`'s appear/disappear. `min()` is the top-most visible page and
    /// the reliable source for mid-chapter progress reporting.
    @State private var visiblePages: Set<Int> = []
    /// The last 1-based page sent to the backend for the current chapter, so we
    /// never re-send an unchanged position (including the resume position).
    @State private var lastSentPage: Int?
    /// Page count of the open chapter, used to report the *last* page (→ `read`)
    /// once the reader reaches the real bottom.
    @State private var pageCount = 0
    /// Whether the reader has scrolled to the chapter's actual end. Once true it
    /// stays true until the chapter changes (seeing the last page means read),
    /// so progress is reported as `pageCount` even after scrolling back up.
    @State private var reachedEnd = false
    /// Debounce for progress writes: replaced on every scroll change, flushed on
    /// leave. Kept as state so we can cancel it across renders.
    @State private var saveTask: Task<Void, Never>?
    /// One-shot flag consumed by `loadPages`: when the reader auto-advances past
    /// the bottom, the incoming chapter restarts at page 1 (ignoring its saved
    /// resume position) and overwrites the store to page 1. Explicit jumps
    /// (chevrons / chapter list) leave it false and resume as usual.
    @State private var forceRestart = false
    /// Bumped by the reader's reload control; each `ReaderPage` re-requests only
    /// if it is currently in the failure state (loaded pages stay put).
    @State private var retryAllToken = 0
    @Environment(\.comicRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    /// How far the reader must be pulled *past* the bottom (points of overscroll)
    /// before advancing to the next chapter.
    private let pullThreshold: CGFloat = 120

    /// How long scrolling must settle before a progress write is sent.
    private let saveDebounce: Duration = .seconds(0.9)

    init(comic: Comic, initialChapter: Chapter) {
        self.comic = comic
        _currentChapter = State(initialValue: initialChapter)
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
        // Save the last position when the reader is dismissed (back button).
        .onDisappear { flushProgress() }
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
                ForEach(Array(urls.enumerated()), id: \.offset){ index, url in
                    ReaderPage(
                        url: url,
                        retryAllToken: retryAllToken,
                        onRetryAll: { retryAllToken += 1 },
                        onVisible: { isVisible in
                            if isVisible {
                                visiblePages.insert(index)
                            } else {
                                visiblePages.remove(index)
                            }
                        }
                    )
                }
            }
            // Marks the pages as scroll targets so `.scrollPosition` can both
            // resume to a page and report the top-most visible page index.
            .scrollTargetLayout()
        }
        // Resume only: setting `topPage` after load (see `loadPages`) scrolls to
        // the resume page. Its reported value is not used for progress.
        .scrollPosition(id: $topPage, anchor: .top)
        // Debounced progress reporting whenever the top-most visible page changes.
        .onChange(of: visiblePages) { _, _ in scheduleProgressSave() }
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
                // Auto-advance restarts the next chapter from the top, unlike an
                // explicit jump which resumes at its saved position.
                goTo(nextChapter, restart: true)
            }
        }
        // Reaching the *actual* bottom (not the pull-past threshold) means the
        // last page has been seen. The top-most visible page is never the final
        // page in a long chapter, so without this the reader could never report
        // `pageCount` and the backend would never mark the chapter `read`.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let maxScroll = geometry.contentSize.height - geometry.containerSize.height
            guard maxScroll > 0 else { return false }
            return geometry.contentOffset.y >= maxScroll - 1
        } action: { wasAtEnd, isAtEnd in
            if isAtEnd && !wasAtEnd && !reachedEnd {
                reachedEnd = true
                scheduleProgressSave()
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
                    goTo(chapter)
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

    /// Switches chapters. `restart: true` (auto-advance) makes the incoming
    /// chapter start at page 1 and overwrite its saved progress; `false`
    /// (chevrons / chapter list) resumes it at its saved position.
    private func goTo(_ chapter: Chapter?, restart: Bool = false) {
        guard let chapter else { return }
        // Persist the outgoing chapter's position before switching, since the
        // scroll view (and `topPage`) is rebuilt for the incoming chapter.
        flushProgress()
        forceRestart = restart
        currentChapter = chapter
    }

    // MARK: - Loading

    private func loadPages() async {
        // Consume the one-shot restart flag for this chapter open.
        let restart = forceRestart
        forceRestart = false

        pagesState = .loading
        do {
            let chapter = try await repository.readerChapter(
                comicID: comic.id,
                chapterID: currentChapter.id
            )
            let urls = chapter.pageURLs
            // Resume: map the 1-based `lastReadPage` to a 0-based index, clamped
            // in case the chapter shrank since progress was saved. `nil` starts
            // at the top. On a restart (auto-advance) we ignore the saved page
            // and force the top. Setting `topPage` in the same update that flips
            // to `.loaded` positions the freshly built scroll view accordingly.
            let resumeIndex: Int?
            if restart {
                resumeIndex = urls.isEmpty ? nil : 0
            } else {
                resumeIndex = chapter.lastReadPage.flatMap { page in
                    urls.isEmpty ? nil : min(max(page - 1, 0), urls.count - 1)
                }
            }
            pagesState = .loaded(urls)
            topPage = resumeIndex
            pageCount = urls.count
            reachedEnd = false
            // Fresh visibility set for the incoming chapter; the new pages
            // repopulate it as they appear.
            visiblePages = []

            if restart {
                // Overwrite the store to page 1 for the incoming chapter, even if
                // it was previously `read`. Clear `lastSentPage` first so the
                // write is not de-duped against the outgoing chapter's value.
                lastSentPage = nil
                sendProgress(
                    page: urls.isEmpty ? nil : 1,
                    comicID: comic.id,
                    chapterID: currentChapter.id
                )
            } else {
                // Seed `lastSentPage` so the resume position is not re-sent.
                lastSentPage = resumeIndex.map { $0 + 1 }
            }
        } catch {
            pagesState = .failed(error)
        }
    }

    // MARK: - Progress reporting

    /// The 1-based page to report: the chapter's last page once the reader has
    /// reached the real bottom (so the backend can mark it `read`), otherwise the
    /// top-most visible page (`visiblePages.min()`, reliable on a lazy stack).
    /// `nil` before the first layout (empty set) → `sendProgress` ignores it.
    private var reportedPage: Int? {
        reachedEnd ? pageCount : visiblePages.min().map { $0 + 1 }
    }

    /// Restarts the debounce so a rapid scroll only writes once it settles.
    /// The debounced task reads `reportedPage` after the sleep, so it reports the
    /// latest position; it is cancelled by `flushProgress` before any chapter
    /// change, so it only ever fires for the still-open chapter.
    private func scheduleProgressSave() {
        saveTask?.cancel()
        let comicID = comic.id
        let chapterID = currentChapter.id
        saveTask = Task {
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            sendProgress(page: reportedPage, comicID: comicID, chapterID: chapterID)
        }
    }

    /// Sends the current position immediately (e.g. on leave / chapter change),
    /// cancelling any pending debounce first. Reads `reportedPage` synchronously
    /// because the caller may reset it (a new chapter) right after.
    private func flushProgress() {
        saveTask?.cancel()
        saveTask = nil
        sendProgress(page: reportedPage, comicID: comic.id, chapterID: currentChapter.id)
    }

    /// Writes `page` for `chapterID`, but only when it changed from the last
    /// value sent. Failures are swallowed: a down progress store must never
    /// interrupt reading.
    private func sendProgress(page: Int?, comicID: String, chapterID: String) {
        guard let page, page != lastSentPage else { return }
        lastSentPage = page
        Task {
            try? await repository.saveProgress(
                comicID: comicID,
                chapterID: chapterID,
                lastPage: page
            )
        }
    }
}

/// A single reading page. `AuthorizedAsyncImage` (see `Shared/AuthorizedAsyncImage.swift`
/// — a stand-in for `AsyncImage` that attaches Cloudflare Access headers)
/// provides the real loading state deferred in M3. Because it has no
/// built-in retry, a failed page would stay failed forever, so the failure
/// placeholder is tappable: tapping bumps `reloadToken`, which re-keys the
/// view so it re-issues the request.
private struct ReaderPage: View {
    let url: URL
    /// Shared token from the reader. A change re-requests this page only when it
    /// is currently failed.
    let retryAllToken: Int
    /// Tapping any failed page's retry button reloads every failed page at once
    /// (bumps the shared `retryAllToken` in the parent).
    let onRetryAll: () -> Void
    /// Reports this page entering (`true`) / leaving (`false`) the viewport, so
    /// the reader can track the top-most visible page for progress reporting.
    let onVisible: (Bool) -> Void
    @State private var reloadToken = 0
    /// Whether this page's image is currently in the failure state, so the
    /// reader-level reload can skip pages that already loaded.
    @State private var hasFailed = false

    var body: some View {
        // Wrap the page so `.id(reloadToken)` re-keys only the inner image view.
        // If `.id` were applied to this view's body root, every ReaderPage would
        // expose the same id (0) to the enclosing LazyVStack — a collision that
        // makes SwiftUI unable to tell the pages apart and breaks scrolling.
        VStack(spacing: 0) {
            AuthorizedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .onAppear { hasFailed = false }
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .onAppear { hasFailed = false }
                case .failure:
                    failurePlaceholder
                        .onAppear { hasFailed = true }
                @unknown default:
                    failurePlaceholder
                        .onAppear { hasFailed = true }
                }
            }
            // Re-issue the request when the retry token changes.
            .id(reloadToken)
        }
        // Reader-level reload: only failed pages re-request; loaded ones stay put.
        .onChange(of: retryAllToken) { _, _ in
            if hasFailed { reloadToken += 1 }
        }
        // Report viewport membership so the reader can derive the top page.
        .onAppear { onVisible(true) }
        .onDisappear { onVisible(false) }
    }

    private var failurePlaceholder: some View {
        Button {
            // Retry every currently-failed page at once, not just this one.
            onRetryAll()
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
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[1].id
        )
    }
}

#Preview("Reader — load failed") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[0].id
        )
        .environment(\.comicRepository, FailingPreviewRepository())
    }
}
