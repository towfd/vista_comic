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
                comicID: comicID,
                chapterID: chapterID,
                pageNumber: pageNumber,
                recognizer: ocrRecognizer,
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
        guard let cgImage = decodedImage?.cgImage else { return }
        let imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let cropRect = SelectionCropMapping.cropRect(
            for: rect,
            displayFrameSize: displayFrameSize,
            imagePixelSize: imagePixelSize
        )
        guard cropRect != .zero, let croppedCGImage = cgImage.cropping(to: cropRect) else { return }
        croppedSelection = CroppedSelection(image: UIImage(cgImage: croppedCGImage))
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

/// One completed selection crop, shown for confirmation. `Identifiable` so it
/// can drive `.sheet(item:)` directly — a fresh selection always presents a
/// fresh sheet instance, even if a prior one was dismissed without change.
/// No recognition, no editing, no persistence yet: that is Ticket 05.
private struct CroppedSelection: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Runs OCR recognition for a confirmed crop and maps the outcome onto
/// `LoadState` (`ComicRepository.swift`'s established async-fetch pattern),
/// so `CroppedSelectionPreview` only has to render three cases instead of
/// re-deriving success/failure handling itself.
///
/// A free function rather than logic embedded directly in the view's
/// `.task`, specifically so the selection → recognize step is unit-testable
/// against a stub `OCRRecognizer` independent of any SwiftUI rendering —
/// mirroring why `SelectionCropMapping` (Ticket 02) and `OCRRecognizer`
/// (Ticket 04) both stayed pure.
func recognizeSelection(_ image: UIImage, using recognizer: any OCRRecognizer) async -> LoadState<String> {
    guard let cgImage = image.cgImage else {
        // Defensive boundary case: every crop produced by `produceCrop` comes
        // from `CGImage.cropping(to:)`, so this should be unreachable in
        // practice, but a `UIImage` isn't guaranteed to carry `cgImage`.
        return .failed(OCRRecognitionError.underlying("Selected image has no pixel data"))
    }
    do {
        let text = try await recognizer.recognizeText(in: cgImage)
        return .loaded(text)
    } catch {
        return .failed(error)
    }
}

/// Runs translation for `text` into `targetLanguage` through a `Translator`,
/// mapped onto `LoadState` — the same reasoning as `recognizeSelection`
/// above, kept as its own free function (not folded into recognition) since
/// translation is a separate, on-demand lifecycle rather than something that
/// runs automatically on appear. Unit-testable against a stub `Translator`
/// independent of any SwiftUI rendering or the real `Translation` framework.
func translateSelection(
    _ text: String,
    to targetLanguage: Locale.Language,
    using translator: any Translator
) async -> LoadState<String> {
    do {
        let translated = try await translator.translate(text, to: targetLanguage)
        return .loaded(translated)
    } catch {
        return .failed(error)
    }
}

/// Persists an original/translated text pair and its source reference
/// through a `TranslationRepository`, mapped onto `LoadState` — the same
/// reasoning as `recognizeSelection`/`translateSelection` above: kept as its
/// own free function so `CroppedSelectionPreview`'s "Save" action is
/// unit-testable against a stub `TranslationRepository` independent of any
/// SwiftUI rendering or the real backend.
func saveSelection(
    originalText: String,
    translatedText: String,
    targetLanguage: String,
    comicID: String,
    chapterID: String,
    pageNumber: Int,
    using repository: any TranslationRepository
) async -> LoadState<SavedTranslation> {
    do {
        let saved = try await repository.save(
            originalText: originalText,
            translatedText: translatedText,
            targetLanguage: targetLanguage,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber
        )
        return .loaded(saved)
    } catch {
        return .failed(error)
    }
}

/// Recognition result for a confirmed text selection (Ticket 05 of
/// `ocr-recognition`; extended additively by `ocr-translation` ticket 04):
/// recognizes the crop on appear, then shows the text pre-filled in an
/// editable field so the user can correct misreads. Once recognition has
/// succeeded, a "Translate" action becomes available to translate the
/// current (possibly user-corrected) text into a picked target language.
/// Once a translation is showing, a "Save" action persists the
/// original/translated pair and its source reference to the backend
/// (`ocr-translation` ticket 05). Dismissing — with or without edits,
/// translated or saved or not — only discards in-memory state; a
/// successfully saved pair already exists in the backend by that point, which
/// is the whole point of saving.
private struct CroppedSelectionPreview: View {
    let image: UIImage
    /// The comic/chapter/page this crop was selected from, threaded down
    /// from `ReaderPage` — needed so "Save" can attach the correct source
    /// reference, mirroring `ComicRepository.saveProgress`'s use of the same
    /// three values elsewhere in this file.
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// Passed in explicitly by `ReaderPage` rather than read from the
    /// environment here, so this view stays a plain consumer of the
    /// recognizer it's given (CLAUDE.md: pass data/actions into reusable
    /// views instead of hard-coding production behavior inside them).
    let recognizer: any OCRRecognizer
    /// Same reasoning as `recognizer` above, for the "Translate" action.
    let translator: any Translator
    /// Same reasoning as `recognizer`/`translator` above, for the "Save"
    /// action.
    let translationRepository: any TranslationRepository
    @Environment(\.dismiss) private var dismiss
    @State private var recognitionState: LoadState<String> = .loading
    /// User-editable text, seeded from a successful recognition. Purely for
    /// on-screen display/correction — never written anywhere.
    @State private var editedText = ""
    /// Translation state, deliberately separate from `recognitionState`:
    /// recognition runs automatically on appear, translation runs on demand
    /// (tapping "Translate") and can be re-run against a different language
    /// or a further-edited text without disturbing the recognition result.
    /// `nil` until the user taps "Translate" for the first time.
    @State private var translationState: LoadState<String>?
    /// Save state, deliberately separate from `translationState` for the same
    /// reason translation is separate from recognition: saving is a further
    /// on-demand step (tapping "Save"), not something that runs
    /// automatically once a translation appears. `nil` until the user taps
    /// "Save" for the first time; reset back to `nil` whenever a fresh
    /// translation replaces the one it was saved from, so a stale "Saved"
    /// indicator never sticks to a different translation.
    @State private var saveState: LoadState<SavedTranslation>?
    /// The target language, defaulting to the last-used one (or Traditional
    /// Chinese on first use — see `LastUsedTargetLanguage`). Persisted back
    /// to `UserDefaults` whenever the user changes the picker.
    @State private var selectedLanguageID = LastUsedTargetLanguage.id

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 180)

                    resultContent

                    if canTranslate {
                        Divider()
                        translateSection
                    }
                }
                .padding()
            }
            .navigationTitle("Selected text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await recognize() }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch recognitionState {
        case .loading:
            HStack {
                Spacer()
                ProgressView("Recognizing text…")
                Spacer()
            }
            .frame(minHeight: 120)
        case .loaded:
            // Editable, not read-only: the whole point of showing recognized
            // text is letting the user fix a misread in place.
            TextEditor(text: $editedText)
                .font(AppFont.caption)
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                }
        case .failed(let error):
            failureContent(for: error)
        }
    }

    private func failureContent(for error: Error) -> some View {
        VStack(spacing: 12) {
            failureMessage(for: error)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Retry") { Task { await recognize() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryRed)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    /// Distinct, localization-ready messages per `OCRRecognitionError` case
    /// (Ticket 04's whole point in making them distinguishable — never
    /// collapsed into one generic "recognition failed" message), plus a
    /// fallback for a conformer that throws something else.
    @ViewBuilder
    private func failureMessage(for error: Error) -> some View {
        if let ocrError = error as? OCRRecognitionError {
            switch ocrError {
            case .noTextFound:
                Text("No text was found in the selected region. Try selecting a tighter area around the text.")
            case .lowConfidence:
                Text("The recognized text wasn't clear enough to show reliably. Try a larger or clearer selection.")
            case .underlying:
                Text("Text recognition failed unexpectedly.")
            }
        } else {
            Text("Recognition failed. You can try again.")
        }
    }

    private func recognize() async {
        recognitionState = .loading
        let result = await recognizeSelection(image, using: recognizer)
        recognitionState = result
        if case .loaded(let text) = result {
            editedText = text
        }
    }

    // MARK: - Translation

    /// The "Translate" action (and the language picker alongside it) only
    /// makes sense once there is recognized — possibly user-corrected — text
    /// to translate; recognition failing or still running leaves nothing to
    /// act on.
    private var canTranslate: Bool {
        guard case .loaded = recognitionState else { return false }
        return !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTranslating: Bool {
        if case .loading = translationState { return true }
        return false
    }

    private var selectedLanguage: Locale.Language {
        Locale.Language(identifier: selectedLanguageID)
    }

    private var translateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Translate to")
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
                Picker("Translate to", selection: $selectedLanguageID) {
                    ForEach(TargetLanguageOption.options) { option in
                        Text(option.nameKey).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: selectedLanguageID) { _, newValue in
                    LastUsedTargetLanguage.id = newValue
                }
                Spacer()
            }

            Button("Translate") {
                Task { await translate() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryRed)
            .disabled(isTranslating)
            .frame(maxWidth: .infinity)

            translationResultContent
        }
    }

    @ViewBuilder
    private var translationResultContent: some View {
        // `translationState` is `nil` until "Translate" is tapped once;
        // unwrap explicitly rather than relying on optional/enum pattern
        // sugar, so each case below is unambiguous.
        if let translationState {
            switch translationState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Translating…")
                    Spacer()
                }
                .frame(minHeight: 80)
            case .loaded(let translated):
                VStack(alignment: .leading, spacing: 12) {
                    // Original and translated text side by side, so the user
                    // can compare them directly without scrolling between two
                    // screens.
                    HStack(alignment: .top, spacing: 12) {
                        translationColumn(titleKey: "Original", text: editedText)
                        Divider()
                        translationColumn(titleKey: "Translation", text: translated)
                    }

                    // "Save" is available as soon as a translation is
                    // showing (`ocr-translation` ticket 05's AC).
                    saveControl(translatedText: translated)
                }
            case .failed(let error):
                translationFailureContent(for: error)
            }
        }
    }

    private func translationColumn(titleKey: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(AppFont.rowTitle)
            Text(text)
                .font(AppFont.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func translationFailureContent(for error: Error) -> some View {
        VStack(spacing: 12) {
            translationFailureMessage(for: error)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await translate() } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    /// Distinct, localization-ready messages per `TranslationError` case,
    /// mirroring `failureMessage(for:)` above for `OCRRecognitionError` —
    /// same reasoning: never collapse distinguishable failures into one
    /// generic message.
    @ViewBuilder
    private func translationFailureMessage(for error: Error) -> some View {
        if let translationError = error as? TranslationError {
            switch translationError {
            case .languagePackUnavailable:
                Text("This language isn't downloaded for on-device translation yet. Download it in Settings, then try again.")
            case .underlying:
                Text("Translation failed unexpectedly.")
            }
        } else {
            Text("Translation failed. You can try again.")
        }
    }

    private func translate() async {
        translationState = .loading
        // A fresh translation invalidates any prior save (it was saved from
        // the previous translated text), so start "Save" clean again.
        saveState = nil
        translationState = await translateSelection(editedText, to: selectedLanguage, using: translator)
    }

    // MARK: - Save

    /// Persists `translatedText` (the current translation result) alongside
    /// the current edited original text, target language, and source
    /// reference.
    private func save(translatedText: String) async {
        saveState = .loading
        saveState = await saveSelection(
            originalText: editedText,
            translatedText: translatedText,
            targetLanguage: selectedLanguageID,
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            using: translationRepository
        )
    }

    @ViewBuilder
    private func saveControl(translatedText: String) -> some View {
        if let saveState {
            switch saveState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Saving…")
                    Spacer()
                }
            case .loaded:
                HStack {
                    Spacer()
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(.primaryRed)
                    Spacer()
                }
            case .failed:
                saveFailureContent(translatedText: translatedText)
            }
        } else {
            // Available as soon as a translation is showing (the AC's whole
            // requirement) — no extra gating beyond that. Once tapped,
            // `saveState` becomes non-nil and this branch (along with the
            // button) is replaced by the loading/loaded/failed state above,
            // so there's no double-tap window to guard against separately.
            Button("Save") { Task { await save(translatedText: translatedText) } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
                .frame(maxWidth: .infinity)
        }
    }

    /// A clear, non-silent failure message (the AC's explicit requirement),
    /// mirroring `failureContent(for:)`/`translationFailureContent(for:)`'s
    /// retry pattern above. Not broken out per distinguishable error case
    /// like OCR/translation failures are — `TranslationRepository.save`
    /// throws generic networking errors (`APIError`), not a save-specific
    /// enum, so one clear message covers it.
    private func saveFailureContent(translatedText: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't save this translation. Check your connection and try again.")
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await save(translatedText: translatedText) } }
                .buttonStyle(.borderedProminent)
                .tint(.primaryRed)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Persists the OCR result screen's last-used translation target language
/// locally (`UserDefaults`) — a lightweight per-device UI preference, not
/// learning material, so it doesn't need backend storage (see the
/// `ocr-translation` spec's rationale). First-ever default is Traditional
/// Chinese, per Ticket 04.
private enum LastUsedTargetLanguage {
    private static let defaultsKey = "ocrTranslation.lastTargetLanguageID"
    static let defaultID = "zh-Hant"

    static var id: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? defaultID }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

/// A curated, non-exhaustive set of target languages offered by the
/// translate picker (Ticket 04) — not every language Apple's `Translation`
/// framework supports, since that would clutter a picker meant for a
/// specific reading-comprehension flow; a short, sensible list is enough.
/// Traditional Chinese is first, matching the default-language decision.
/// `id` doubles as the value persisted via `LastUsedTargetLanguage` and as a
/// `Locale.Language(identifier:)` string (e.g. `Locale.Language(identifier:
/// "zh-Hant")` resolves to the same language as `AppleTranslator`'s own
/// `Locale.Language(languageCode: "zh", script: "Hant")` construction).
private struct TargetLanguageOption: Identifiable {
    let id: String
    let nameKey: LocalizedStringKey

    static let options: [TargetLanguageOption] = [
        TargetLanguageOption(id: "zh-Hant", nameKey: "Traditional Chinese"),
        TargetLanguageOption(id: "en", nameKey: "English"),
        TargetLanguageOption(id: "ja", nameKey: "Japanese"),
        TargetLanguageOption(id: "ko", nameKey: "Korean"),
        TargetLanguageOption(id: "fr", nameKey: "French"),
        TargetLanguageOption(id: "es", nameKey: "Spanish"),
    ]
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

#Preview("Reader — peek from 單字本") {
    NavigationStack {
        ComicView(
            comicID: SampleData.comics[0].id,
            chapterID: SampleData.comics[0].chapters[1].id,
            targetPage: 3,
            isPeek: true
        )
    }
}
