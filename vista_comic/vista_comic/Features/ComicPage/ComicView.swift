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
//  Reader, page and progress code only. The confirmed-crop model and the
//  selection action functions live in `SelectionActions.swift`; the result
//  sheet those actions drive lives in `components/CroppedSelectionPreview.swift`
//  (split out in `comprehension-response-ux` ticket 13).
//
import SwiftUI
import UIKit

/// Ids-based entry to the reader. Loads the comic detail so the reader can offer
/// prev/next navigation and the chapter-list sheet even when the caller (e.g. the
/// library card) only knows the comic and chapter ids.
struct ComicView: View {
    let comicID: String
    let chapterID: String
    /// 1-based page to scroll to on open, overriding the chapter's saved
    /// resume position. See `ReaderRoute.targetPage`.
    var targetPage: Int? = nil
    /// Read-only preview: never writes progress. See `ReaderRoute.isPeek`.
    var isPeek: Bool = false

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
                ReaderView(comic: comic, initialChapter: initial, initialTargetPage: targetPage, isPeek: isPeek)
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
    /// One-shot: consumed by the first `loadPages()` call, then cleared, so
    /// prev/next chapter navigation within the same session resumes normally
    /// instead of re-applying the originally requested page.
    @State private var initialTargetPage: Int?
    /// Sticky for the lifetime of this `ReaderView` instance — once opened as
    /// a preview, no navigation within it (prev/next chapter, chapter list,
    /// auto-advance) ever writes progress. See `ReaderRoute.isPeek`.
    let isPeek: Bool
    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var showChapterList = false
    /// Whether the Reader is in text-selection mode (Ticket 03 of
    /// `ocr-recognition`). While true, the pages `ScrollView` is disabled and
    /// the tap-to-toggle-controls gesture is suppressed so a drag over a page
    /// draws a selection rectangle instead of scrolling or hiding controls.
    @State private var isSelecting = false
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

    init(comic: Comic, initialChapter: Chapter, initialTargetPage: Int? = nil, isPeek: Bool = false) {
        self.comic = comic
        _currentChapter = State(initialValue: initialChapter)
        _initialTargetPage = State(initialValue: initialTargetPage)
        self.isPeek = isPeek
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
                        comicID: comic.id,
                        chapterID: currentChapter.id,
                        // 1-based, matching `Progress.lastPage`'s and
                        // `SavedTranslation.pageNumber`'s convention.
                        pageNumber: index + 1,
                        retryAllToken: retryAllToken,
                        isSelecting: isSelecting,
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
        // Selection mode owns the drag gesture on the current page instead;
        // disabling scroll while selecting stops the ScrollView from fighting
        // that drag for the touch.
        .scrollDisabled(isSelecting)
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
            // A tap while selecting shouldn't hide the very controls (the
            // selection-mode toggle) needed to exit selection mode.
            guard !isSelecting else { return }
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
                Button {
                    withAnimation {
                        isSelecting.toggle()
                        // Selecting requires the controls (this very button)
                        // to stay reachable, so force them visible on entry.
                        if isSelecting { showControls = true }
                    }
                } label: {
                    Image(systemName: isSelecting ? "text.viewfinder" : "character.cursor.ibeam")
                        .foregroundStyle(isSelecting ? Color.primaryRed : Color.primary)
                }
                .accessibilityLabel(isSelecting ? "Exit text selection" : "Select text")
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

                VStack(spacing: 2) {
                    Text(currentChapter.title)
                        .font(AppFont.rowTitle)
                    // Sets expectation up front that this session won't
                    // advance "last read" — otherwise a preview reader looks
                    // identical to a normal one and the missing progress
                    // update would look like a bug.
                    if isPeek {
                        Text("Preview — progress won't be saved")
                            .font(AppFont.caption)
                            .foregroundStyle(.grayFont)
                    }
                }

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
        // Consume the one-shot initial target page (set only by the route
        // that opened this reader) so later chapter changes resume normally.
        let targetPage = initialTargetPage
        initialTargetPage = nil

        pagesState = .loading
        do {
            let chapter = try await repository.readerChapter(
                comicID: comic.id,
                chapterID: currentChapter.id
            )
            let urls = chapter.pageURLs
            // Resume: map the 1-based `lastReadPage` (or, on first open, an
            // explicit `targetPage` override — see `ReaderRoute.targetPage`)
            // to a 0-based index, clamped in case the chapter shrank since
            // that page number was recorded. `nil` starts at the top. On a
            // restart (auto-advance) we ignore both and force the top.
            // Setting `topPage` in the same update that flips to `.loaded`
            // positions the freshly built scroll view accordingly.
            let resumeIndex: Int?
            if restart {
                resumeIndex = urls.isEmpty ? nil : 0
            } else if let targetPage {
                resumeIndex = urls.isEmpty ? nil : min(max(targetPage - 1, 0), urls.count - 1)
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
    /// interrupt reading. A no-op in `isPeek` mode — the single gate every
    /// progress write (scroll debounce, flush-on-leave, restart-on-advance)
    /// funnels through, so a preview reader never touches saved progress.
    private func sendProgress(page: Int?, comicID: String, chapterID: String) {
        guard !isPeek else { return }
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
    /// The comic/chapter this page belongs to, and this page's 1-based
    /// position within the chapter — threaded down from `ReaderView` (which
    /// already carries `comic.id`/`currentChapter.id` for progress-saving)
    /// so a confirmed selection's "Save" action (`ocr-translation` ticket 05)
    /// knows which source reference to save against.
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// Shared token from the reader. A change re-requests this page only when it
    /// is currently failed.
    let retryAllToken: Int
    /// Whether the Reader is in text-selection mode. Drives whether this page
    /// installs the drag-to-select overlay/gesture over its rendered image.
    let isSelecting: Bool
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
    /// The decoded source `UIImage` behind the rendered `Image`, captured via
    /// `AuthorizedAsyncImage`'s `onDecoded` callback (Ticket 01). Cropping
    /// reads pixels from this, not from the scaled-down on-screen rendering.
    @State private var decodedImage: UIImage?
    /// The in-progress selection rectangle, in the image's display-frame
    /// coordinate space (see `SelectionCropMapping`'s doc comment). `nil`
    /// when no drag is active.
    @State private var selectionRect: CGRect?
    /// Whether the drag's current location is inside the cancel zone (see
    /// `cancelZoneFrame`), so the badge can visually confirm "release here to
    /// cancel" before the finger lifts.
    @State private var isHoveringCancelZone = false
    /// The most recently produced crop, shown in a confirmation sheet.
    @State private var croppedSelection: CroppedSelection?
    /// The recognizer `CroppedSelectionPreview` runs the confirmed crop
    /// through (Ticket 05). Read here — the owner of `croppedSelection` — and
    /// passed down explicitly rather than having that view reach into the
    /// environment itself (CLAUDE.md: pass data/actions into reusable views).
    @Environment(\.ocrRecognizer) private var ocrRecognizer
    /// The translator `CroppedSelectionPreview`'s "Translate" action runs
    /// through (`ocr-translation` ticket 04). Read here for the same reason
    /// as `ocrRecognizer` above, rather than that view reaching into the
    /// environment itself.
    @Environment(\.translator) private var translator
    /// The repository `CroppedSelectionPreview`'s "Save" action runs through
    /// (`ocr-translation` ticket 05). Same reasoning as `ocrRecognizer`/
    /// `translator` above.
    @Environment(\.translationRepository) private var translationRepository
    /// The comprehender `CroppedSelectionPreview`'s "Translate" action now
    /// calls first (`llm-comprehension` ticket 14), falling back to
    /// `translator` above only on a declined/failed cloud call. Same
    /// reasoning as the other environment reads on this view: read here and
    /// passed down explicitly.
    @Environment(\.comprehender) private var comprehender

    /// Fixed-size "release here to cancel" zone anchored to a corner of the
    /// displayed image, so cancelling is possible mid-drag with a single
    /// continuous touch: drag into the badge and lift, instead of drawing a
    /// selection and confirming it. See Ticket 03's cancel requirement.
    private let cancelZoneDiameter: CGFloat = 44

    var body: some View {
        // Wrap the page so `.id(reloadToken)` re-keys only the inner image view.
        // If `.id` were applied to this view's body root, every ReaderPage would
        // expose the same id (0) to the enclosing LazyVStack — a collision that
        // makes SwiftUI unable to tell the pages apart and breaks scrolling.
        VStack(spacing: 0) {
            AuthorizedAsyncImage(url: url, onDecoded: { decodedImage = $0 }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .onAppear { hasFailed = false }
                        .overlay {
                            // Only installed while selecting, so normal
                            // reading gestures are completely unaffected
                            // otherwise.
                            if isSelecting {
                                GeometryReader { proxy in
                                    selectionOverlay(displayFrameSize: proxy.size)
                                }
                            }
                        }
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
        // Leaving selection mode (or scrolling away) mid-drag discards any
        // partial selection rather than leaving a stale rectangle on screen.
        .onChange(of: isSelecting) { _, stillSelecting in
            if !stillSelecting {
                selectionRect = nil
                isHoveringCancelZone = false
            }
        }
        // Report viewport membership so the reader can derive the top page.
        .onAppear { onVisible(true) }
        .onDisappear { onVisible(false) }
        .sheet(item: $croppedSelection) { selection in
            CroppedSelectionPreview(
                image: selection.image,
                pageImage: selection.pageImage,
                comicID: comicID,
                chapterID: chapterID,
                pageNumber: pageNumber,
                recognizer: ocrRecognizer,
                comprehender: comprehender,
                translator: translator,
                translationRepository: translationRepository
            )
        }
    }

    // MARK: - Selection

    private func cancelZoneFrame(in displayFrameSize: CGSize) -> CGRect {
        CGRect(
            x: displayFrameSize.width - cancelZoneDiameter - 12,
            y: 12,
            width: cancelZoneDiameter,
            height: cancelZoneDiameter
        )
    }

    private func dragRect(_ value: DragGesture.Value) -> CGRect {
        CGRect(
            x: value.startLocation.x,
            y: value.startLocation.y,
            width: value.translation.width,
            height: value.translation.height
        ).standardized
    }

    private func selectionOverlay(displayFrameSize: CGSize) -> some View {
        let cancelZone = cancelZoneFrame(in: displayFrameSize)
        return ZStack(alignment: .topLeading) {
            // Transparent, but shaped so it still receives the drag — this is
            // the hit-testable surface the gesture is attached to.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            selectionRect = dragRect(value)
                            isHoveringCancelZone = cancelZone.contains(value.location)
                        }
                        .onEnded { value in
                            let cancelled = cancelZone.contains(value.location)
                            let rect = dragRect(value)
                            selectionRect = nil
                            isHoveringCancelZone = false
                            guard !cancelled else { return }
                            produceCrop(from: rect, displayFrameSize: displayFrameSize)
                        }
                )

            if let selectionRect {
                Rectangle()
                    .strokeBorder(Color.primaryRed, lineWidth: 2)
                    .background(Rectangle().fill(Color.primaryRed.opacity(0.15)))
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)

                cancelZoneBadge
                    .frame(width: cancelZoneDiameter, height: cancelZoneDiameter)
                    .position(x: cancelZone.midX, y: cancelZone.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private var cancelZoneBadge: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(isHoveringCancelZone ? Color.white : Color.primaryRed)
            .padding(6)
            .background(
                Circle().fill(isHoveringCancelZone ? Color.primaryRed : Color.white.opacity(0.9))
            )
            .scaleEffect(isHoveringCancelZone ? 1.2 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHoveringCancelZone)
            .accessibilityLabel("Drag here and release to cancel selection")
    }

    /// Maps `rect` (drawn in `displayFrameSize`'s coordinate space) to source
    /// pixels via `SelectionCropMapping` and crops the decoded image — never
    /// a screenshot of the scaled on-screen rendering. A `.zero` mapping (the
    /// selection didn't overlap the displayed image at all) is a no-op.
    private func produceCrop(from rect: CGRect, displayFrameSize: CGSize) {
        guard let decodedImage, let cgImage = decodedImage.cgImage else { return }
        let imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let cropRect = SelectionCropMapping.cropRect(
            for: rect,
            displayFrameSize: displayFrameSize,
            imagePixelSize: imagePixelSize
        )
        guard cropRect != .zero, let croppedCGImage = cgImage.cropping(to: cropRect) else { return }
        croppedSelection = CroppedSelection(image: UIImage(cgImage: croppedCGImage), pageImage: decodedImage)
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
