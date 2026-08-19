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
    /// Drives the pages scroll view programmatically: the resume position when
    /// a chapter loads, and the offset correction when a zoom is committed.
    ///
    /// Write-only, exactly as the `topPage` binding it replaces was — its
    /// *reported* value on a LazyVStack of unknown-height AsyncImages is not
    /// reliable, so it is never read for progress reporting (see `visiblePages`).
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
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
    /// Whether the two scroll-geometry inferences below can be trusted right now.
    ///
    /// Load-bearing, not a convenience: both ask "did the reader scroll past the
    /// end", and scroll geometry alone cannot tell that from "the content got
    /// shorter underneath a stationary reader". The content does get shorter —
    /// pages outside the prefetch window fall back to a 220pt placeholder, and
    /// the keyboard raised for the result sheet's text field recycles rows into
    /// exactly that state. Zoom is deliberately *not* on that list: it is a
    /// transform over the viewport, so it cannot move content height at all,
    /// and it therefore needs no gate of its own.
    @State private var isScrollDriven = false
    /// The settled magnification. `1.0` is today's reader exactly.
    @State private var zoomScale: CGFloat = ReaderZoom.minScale
    /// The live pinch's scale, non-nil only while fingers are down. Absolute
    /// rather than a ratio against anything, which is what keeps the rendered
    /// viewport from ever being drawn smaller than the screen.
    @State private var gestureScale: CGFloat?
    /// How far the magnified strip is moved sideways, in screen points. Zero at
    /// full width, where the pan limit makes it inert anyway.
    @State private var panX: CGFloat = 0
    /// `panX` as it stood when the current sideways drag began, so the drag is
    /// applied as one total translation rather than accumulated per frame.
    @State private var panXAtDragStart: CGFloat?
    /// The vertical shift a pinch needs in order to keep its focal point still.
    ///
    /// Held here only for the duration of the gesture, and handed to the scroll
    /// view exactly when the fingers lift. Vertical movement belongs to the
    /// scroll view; this is the transient form it takes while a pinch is in
    /// flight, when moving the scroll view on every frame would mean animating
    /// it against the gesture.
    @State private var gesturePanY: CGFloat = 0
    /// The vertical shift that makes a chapter's first and last screen readable
    /// while magnified. Derived from the scroll position, and zero everywhere
    /// but within reach of an end — see `ReaderZoom.endOfChapterPan`.
    @State private var endPan: CGFloat = 0
    /// Where the fingers came down, as a unit point within the viewport.
    ///
    /// Captured once when the gesture starts so it cannot drift mid-pinch. Its
    /// horizontal half is resolved through the pan and its vertical half
    /// through the scroll offset, so two mechanisms have to agree — which is
    /// what `applyFocalPoint` exists to keep true.
    @State private var magnifyFocal: UnitPoint = .center
    /// The width the scroll view offers its content, measured rather than
    /// assumed so it follows rotation and iPad multitasking.
    @State private var containerWidth: CGFloat = 0
    /// The height of the same window onto the content, which the pan limits and
    /// the end-of-chapter shift are both expressed against.
    @State private var containerHeight: CGFloat = 0
    /// How tall the top control bar is, so the selection cancel badge can be
    /// placed clear of it. `0` until the controls have been laid out once.
    @State private var controlBarHeight: CGFloat = 0
    /// The scroll view's live offset and content height.
    ///
    /// A reference box rather than `@State` deliberately: this changes on every
    /// frame of every scroll, and holding it in view state would invalidate the
    /// reader's body continuously. Nothing reads it during layout — it is
    /// consulted only when a pinch begins or commits.
    @State private var scrollMetrics = ReaderScrollMetricsBox()
    /// The width the pages are laid out at, measured from the stack itself
    /// rather than assumed, since it changes with rotation and with iPad
    /// multitasking. `0` until the first layout, which `reservedPageHeight`
    /// reads as "no reservation possible yet".
    @State private var pageWidth: CGFloat = 0
    /// This chapter's median height ratio, standing in for pages that have
    /// never been decoded. Recomputed rather than accumulated, because the
    /// cache — not the reader — is where the per-page ratios actually live.
    @State private var chapterHeightRatio: CGFloat?
    /// The crop awaiting confirmation, and the sheet showing it.
    ///
    /// Owned **here** rather than on the page the selection was drawn on. A
    /// `ReaderPage` lives inside a `LazyVStack`, which destroys a row once it
    /// leaves the viewport — taking its `@State`, and therefore any sheet bound
    /// to that state, with it. The keyboard appearing for the text field inside
    /// the sheet shrinks the viewport, which was enough to recycle the owning
    /// page and close the sheet out from under the reader mid-correction (and,
    /// on the way, to re-decode several full-resolution pages on the main
    /// thread, which is where the stall came from). The reader itself is not
    /// recycled, so the sheet outlives any scrolling or resizing beneath it.
    @State private var croppedSelection: CroppedSelection?
    /// The recognizer, translator and repository `CroppedSelectionPreview`
    /// needs. Read here — the owner of `croppedSelection` — and passed down
    /// explicitly rather than having that view reach into the environment
    /// itself (CLAUDE.md: pass data and actions into reusable views).
    @Environment(\.ocrRecognizer) private var ocrRecognizer
    @Environment(\.translator) private var translator
    @Environment(\.comprehensionRepository) private var comprehensionRepository
    @Environment(\.studyRepository) private var studyRepository
    @Environment(\.comicRepository) private var repository
    /// Read here rather than in `ReaderPage` because the *window* is the
    /// reader's business: only this view knows the chapter's whole page list
    /// and where in it the reader currently is. `AuthorizedAsyncImage` reads
    /// the same cache separately for the row it is drawing.
    @Environment(\.pageImageCache) private var pageImageCache
    @Environment(\.chapterDownloads) private var downloads
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
        .sheet(item: $croppedSelection) { selection in
            CroppedSelectionPreview(
                image: selection.image,
                comicID: comic.id,
                chapterID: currentChapter.id,
                pageNumber: selection.pageNumber,
                recognizer: ocrRecognizer,
                translator: translator,
                comprehensionRepository: comprehensionRepository,
                studyRepository: studyRepository
            )
        }
        // Load the current chapter's pages on open, and reload whenever the
        // chapter changes (prev / next / chapter list / auto-advance).
        .task(id: currentChapter.id) { await loadPages() }
        // Tell the download engine what is being read, so the download cap
        // cannot evict the pages out from under it. Re-announced on every
        // chapter change, since that is what "open" means here.
        .onChange(of: currentChapter.id, initial: true) { _, _ in
            downloads.readerOpened(comicID: comic.id, chapterID: currentChapter.id)
        }
        // Save the last position when the reader is dismissed (back button).
        .onDisappear {
            flushProgress()
            downloads.readerClosed()
        }
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
        case .failed(let error):
            // Offline and not downloaded is a different fact from "the server
            // could not be reached", and only the reader can act on it — so the
            // Reader says which it was rather than showing one error for both.
            ErrorStateView(
                kind: error is OfflineReadError ? .notAvailableOffline : .connection
            ) {
                Task { await loadPages() }
            }
        }
    }

    private func pagesScrollView(urls: [URL]) -> some View {
        // One axis, at every magnification. The strip is laid out at exactly
        // the container's width whatever the scale, so there is never anything
        // to scroll horizontally — moving sideways while magnified is a
        // transform offset this view owns, not a second scroll axis.
        ScrollView{
            // Lazy so a long chapter (~100+ pages) doesn't kick off every
            // `AsyncImage` at once; pages load as they scroll into view.
            LazyVStack(spacing: 0){
                // Renders the current chapter's pages as a continuous vertical read.
                ForEach(Array(urls.enumerated()), id: \.offset){ index, url in
                    ReaderPage(
                        url: url,
                        // 1-based, matching `Progress.lastPage`'s and
                        // `ComprehensionRecord.pageNumber`'s convention.
                        pageNumber: index + 1,
                        retryAllToken: retryAllToken,
                        isSelecting: isSelecting,
                        controlBarHeight: controlBarHeight,
                        magnification: zoomScale,
                        viewportPan: CGSize(width: panX, height: endPan),
                        reservedWidth: pageWidth,
                        chapterHeightRatio: chapterHeightRatio,
                        onRetryAll: { retryAllToken += 1 },
                        onVisible: { isVisible in
                            if isVisible {
                                visiblePages.insert(index)
                            } else {
                                visiblePages.remove(index)
                            }
                        },
                        onCrop: { crop in
                            croppedSelection = crop
                            // Selecting text is one action, not a mode to
                            // remember to leave: readers select occasionally
                            // and deliberately, and leaving the mode on meant
                            // closing the sheet onto a reader that would not
                            // scroll. Ends on a crop being *produced* rather
                            // than on the sheet closing, so the reader behind
                            // an iPad form sheet is live rather than frozen
                            // under it. A drag that produced nothing — the
                            // cancel zone, or a selection off the page — never
                            // reaches here, and so stays in selection mode.
                            withAnimation { isSelecting = false }
                        }
                    )
                }
            }
            // Marks the pages as scroll targets so `.scrollPosition` can both
            // resume to a page and report the top-most visible page index.
            .scrollTargetLayout()
            // Measured on the stack rather than on the scroll view, so it is
            // the width the pages are actually laid out at. Under this zoom
            // model that is the container's width at every scale — the pages
            // are never re-laid-out — which is exactly why the reserved page
            // heights need no zoom arithmetic of their own.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
        // The magnification, applied to the *viewport* rather than to its
        // content, and anchored at the centre so that the pan below is the only
        // thing that decides which part of the strip is on screen.
        //
        // Transforming the content would mean transforming a stack tens of
        // thousands of points tall, which is compositing work on a scale the
        // scroll view has no way to avoid. The viewport is one screen.
        .scaleEffect(renderedScale, anchor: .center)
        // Sideways from the reader's own pan; vertically from the
        // end-of-chapter shift plus whatever a pinch in flight needs. Offsets
        // do not participate in layout, so the scroll view above is untouched
        // by either.
        .offset(x: panX, y: endPan + gesturePanY)
        // Keeps the transformed viewport from bleeding outside the reader's
        // bounds.
        .clipped()
        // Selection mode owns the drag gesture on the current page instead;
        // disabling scroll while selecting stops the ScrollView from fighting
        // that drag for the touch.
        .scrollDisabled(isSelecting)
        // Drives the resume position on load and the offset correction when a
        // zoom commits. Never read; see the property's own note.
        .scrollPosition($scrollPosition, anchor: .top)
        // The window onto the strip, measured rather than assumed so rotation
        // and iPad multitasking are followed.
        //
        // No offset correction here any more. A resize used to rescale the
        // whole chapter under a stationary reader, because the laid-out width
        // was derived from this one; now the strip is laid out at the container
        // width at every scale, so a resize changes what is visible and not
        // where the reader is. Only the pan has to be brought back inside the
        // new bounds.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            containerWidth = size.width
            containerHeight = size.height
            panX = ReaderZoom.clampedPan(
                panX, containerLength: size.width, scale: renderedScale
            )
        }
        // Two fingers, so there is nothing to arbitrate against the scroll
        // view's one-finger pan; simultaneous so it composes rather than
        // replaces.
        .simultaneousGesture(magnifyGesture)
        // One finger. The scroll view keeps the vertical component of the same
        // drag and this reads only the horizontal one, so the two never have to
        // arbitrate for the touch.
        .simultaneousGesture(panGesture)
        // Fed into a reference box rather than into view state: this fires on
        // every frame of every scroll, and the reader's body must not be
        // invalidated by it.
        .onScrollGeometryChange(for: ReaderScrollMetrics.self) { geometry in
            ReaderScrollMetrics(
                offset: geometry.contentOffset,
                contentSize: geometry.contentSize,
                containerSize: geometry.containerSize
            )
        } action: { _, metrics in
            scrollMetrics.value = metrics
        }
        // The end-of-chapter shift. Recomputed only when its value actually
        // changes, which at full width is never and while magnified is only
        // within reach of the first or last screen.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            ReaderZoom.endOfChapterPan(
                scrollOffset: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                scale: renderedScale
            )
        } action: { _, pan in
            endPan = pan
        }
        // Two deliberately separate reactions to the same "which pages are
        // visible" signal, because they must behave oppositely: the prefetch
        // window has to slide *immediately* to be of any use, while progress
        // stays debounced so a scroll writes once it settles. Kept as two
        // handlers rather than one convenience that does both — a page fetched
        // ahead of the reader being counted as read would silently corrupt
        // their saved position across the whole library.
        .onChange(of: visiblePages) { _, pages in
            updatePrefetchWindow(pageURLs: urls, visiblePages: pages, cache: pageImageCache)
        }
        .onChange(of: visiblePages) { _, _ in scheduleProgressSave() }
        // A third reaction to the same signal, kept separate for the same
        // reason as the two above: this one neither reaches ahead of the
        // reader nor reports where they are, it re-reads what the cache has
        // learned about this chapter's page shapes. Hung off visibility
        // because that is when new pages have decoded — the median converges
        // in the first few and then barely moves, so this needs no finer
        // signal of its own.
        .onChange(of: visiblePages) { _, _ in refreshChapterHeightRatio(pageURLs: urls) }
        // Feeds the gate both inferences below depend on. What each phase means
        // to it lives on the gate itself, which is also where it is tested.
        // Deceleration counts as driven: releasing a fling that coasts to the
        // bottom is a normal way to finish a chapter, and the geometry update
        // that crosses the threshold usually arrives after the finger has left.
        .onScrollPhaseChange { _, phase in
            isScrollDriven = phase == .tracking
                || phase == .interacting
                || phase == .decelerating
        }
        // Auto-advance: after reaching the bottom, the user must keep pulling
        // *past* the end (overscroll) to continue into the next chapter — so
        // simply reaching the bottom is not enough. Does nothing on the last
        // chapter (nextChapter == nil), and only for content taller than the
        // screen (otherwise there is no bottom to pull past).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            readerPassedBottom(
                contentOffsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                // Deliberately inert while magnified. Not a technical
                // limitation — the geometry is trustworthy at every scale under
                // this model — but a product rule: a reader who has magnified a
                // panel is examining it, and that should never turn into a
                // chapter change. Read-detection below is armed at every scale.
                isScrollDriven: isScrollDriven && zoomScale == ReaderZoom.minScale,
                overscroll: pullThreshold
            )
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
        //
        // Gated on the same phase, and for a consequence of its own rather than
        // by symmetry: a collapse deep in a chapter reads as the bottom, reports
        // `pageCount`, and marks a chapter read the reader never finished.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            readerPassedBottom(
                contentOffsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                isScrollDriven: isScrollDriven,
                overscroll: -1
            )
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

    // MARK: - Zoom

    /// The scale the viewport is rendered at right now — the settled scale,
    /// unless a pinch is in flight.
    private var renderedScale: CGFloat { gestureScale ?? zoomScale }

    /// The pinch.
    ///
    /// Nothing is committed when the fingers lift. The scale the gesture
    /// settles on is simply the scale the transform keeps, so there is no
    /// re-layout and therefore no moment at which the reader can be displaced.
    /// The previous model committed a new layout width here and had to
    /// re-anchor the scroll offset to compensate — an assignment evaluated
    /// against a content size that had not grown yet, and silently clamped
    /// against it. That is the defect this model removes by construction.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let previous = renderedScale
                if gestureScale == nil { magnifyFocal = value.startAnchor }
                let next = ReaderZoom.rubberBanded(zoomScale * value.magnification)
                applyFocalPoint(from: previous, to: next)
                gestureScale = next
            }
            .onEnded { value in
                let previous = renderedScale
                let settled = ReaderZoom.settled(zoomScale * value.magnification)
                applyFocalPoint(from: previous, to: settled)
                zoomScale = settled
                gestureScale = nil
                handVerticalPanToScrollView(at: settled)
            }
    }

    /// Dragging sideways to see the rest of a magnified page.
    ///
    /// Reads only the horizontal component, so the scroll view keeps the
    /// vertical one and the two compose instead of competing. Inert at full
    /// width, where the pan limit is zero anyway, and while selecting, where
    /// the drag belongs to the selection overlay.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !isSelecting, renderedScale > ReaderZoom.minScale else { return }
                let base = panXAtDragStart ?? panX
                panXAtDragStart = base
                panX = ReaderZoom.clampedPan(
                    base + value.translation.width,
                    containerLength: containerWidth,
                    scale: renderedScale
                )
            }
            .onEnded { _ in panXAtDragStart = nil }
    }

    /// Moves the transform so that whatever is under the fingers stays under
    /// the fingers as the scale changes.
    ///
    /// The two axes travel through different mechanisms and have to agree. The
    /// horizontal half goes to the pan the reader owns. The vertical half goes
    /// to `gesturePanY`, which the scroll view takes over from when the gesture
    /// ends — and it is expressed against the *total* vertical shift, so that
    /// the end-of-chapter shift changing with the scale is accounted for rather
    /// than fighting it.
    private func applyFocalPoint(from oldScale: CGFloat, to newScale: CGFloat) {
        panX = ReaderZoom.clampedPan(
            ReaderZoom.panKeepingFocalPoint(
                focal: magnifyFocal.x,
                containerLength: containerWidth,
                previousPan: panX,
                from: oldScale,
                to: newScale
            ),
            containerLength: containerWidth,
            scale: newScale
        )

        let totalPanY = ReaderZoom.panKeepingFocalPoint(
            focal: magnifyFocal.y,
            containerLength: containerHeight,
            previousPan: endPan + gesturePanY,
            from: oldScale,
            to: newScale
        )
        let metrics = scrollMetrics.value
        endPan = ReaderZoom.endOfChapterPan(
            scrollOffset: metrics.offset.y,
            contentHeight: metrics.contentSize.height,
            containerHeight: containerHeight,
            scale: newScale
        )
        gesturePanY = totalPanY - endPan
    }

    /// Converts the pinch's transient vertical shift into a scroll offset, so
    /// that vertical movement ends up where it belongs.
    ///
    /// Exact, and therefore invisible: a point of scrolling moves the content
    /// `scale` points on screen, and content size does not change with the
    /// scale, so there is no stale size for the resulting offset to be clamped
    /// against. The one place it can still clamp is against the ends of the
    /// chapter itself, which is a real limit rather than a stale measurement.
    private func handVerticalPanToScrollView(at scale: CGFloat) {
        guard gesturePanY != 0 else { return }
        let metrics = scrollMetrics.value
        let maxOffset = max(0, metrics.contentSize.height - metrics.containerSize.height)
        let delta = ReaderZoom.scrollOffsetDelta(replacingVerticalPan: gesturePanY, scale: scale)
        let target = min(max(metrics.offset.y + delta, 0), maxOffset)
        gesturePanY = 0
        scrollPosition.scrollTo(point: CGPoint(x: 0, y: target))
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
            // How much of the reader this bar covers. Selection mode forces the
            // controls visible, so the selection cancel badge has to be placed
            // below this or it is drawn correctly and still cannot be seen.
            // Measured rather than assumed because the bar grows with Dynamic
            // Type.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlBarHeight = $0 }

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
        // Drop the outgoing chapter's pages *here* rather than leaving it to
        // `loadPages()`. `.task(id:)` only runs after a render, so between this
        // assignment and that task there was one pass carrying the incoming
        // chapter's `.id` over the outgoing chapter's URLs and a stale
        // `topPage` — a freshly built scroll view scrolled deep into content of
        // mostly placeholder-height rows, which is how a single false advance
        // became a run to the last chapter.
        pagesState = .loading
        // The rebuilt scroll view starts idle, and the incoming chapter starts
        // at full width. Carrying either across would let the new chapter's very
        // first geometry reading be taken for a pull the reader never made.
        isScrollDriven = false
        zoomScale = ReaderZoom.minScale
        gestureScale = nil
        panX = 0
        panXAtDragStart = nil
        gesturePanY = 0
        endPan = 0
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
            // Setting the scroll position in the same update that flips to
            // `.loaded` positions the freshly built scroll view accordingly.
            let resumeIndex = readerStartIndex(
                pageCount: urls.count,
                restart: restart,
                targetPage: targetPage,
                lastReadPage: chapter.lastReadPage
            )
            pagesState = .loaded(urls)
            // A rebuilt scroll view already starts at the top, so "no saved
            // position" needs no instruction — just a position holding nothing.
            scrollPosition = resumeIndex.map { ScrollPosition(id: $0, anchor: .top) }
                ?? ScrollPosition(idType: Int.self)
            pageCount = urls.count
            reachedEnd = false
            // Fresh visibility set for the incoming chapter; the new pages
            // repopulate it as they appear.
            visiblePages = []

            // Start fetching the moment the chapter opens, seeded at the page
            // the reader is actually about to look at — the resume position, a
            // history jump's target, or the top on an auto-advance restart —
            // rather than unconditionally at page 1, which would leave a
            // reader resuming mid-chapter waiting for pages they will never
            // scroll back to. `nil` means "no saved position", i.e. the top.
            //
            // A chapter change re-seeds the window; it never clears the cache,
            // which is what keeps flipping to an adjacent chapter and back
            // instant.
            pageImageCache.setPrefetchWindow(pageURLs: urls, currentIndex: resumeIndex ?? 0)

            // Seed from whatever the cache already knows about this chapter —
            // re-entering one read earlier reserves correct heights from the
            // first frame, rather than starting from the library default and
            // visibly settling.
            refreshChapterHeightRatio(pageURLs: urls)

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

    /// Re-reads the chapter's known page proportions from the cache and keeps
    /// their median as the stand-in for pages not yet decoded.
    ///
    /// Recomputed from the cache rather than accumulated here, so it is right
    /// after an eviction, after a memory warning, and on re-entering a chapter
    /// read earlier in the session — none of which the reader would otherwise
    /// hear about. Holds the previous value when nothing is known yet, so a
    /// fresh chapter does not first un-reserve every height it had.
    private func refreshChapterHeightRatio(pageURLs: [URL]) {
        let known = pageURLs.compactMap { pageImageCache.heightRatio(for: $0) }
        if let median = medianHeightRatio(of: known) {
            chapterHeightRatio = median
        }
    }

    // MARK: - Progress reporting

    /// The 1-based page to report. See `reportedProgressPage`.
    private var reportedPage: Int? {
        reportedProgressPage(
            visiblePages: visiblePages,
            reachedEnd: reachedEnd,
            pageCount: pageCount
        )
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

// MARK: - What the reader derives from "which pages are visible"
//
// Two free functions rather than two methods on `ReaderView`, so both can be
// tested without rendering the reader — and so the difference between them is
// legible at a glance. They read the same input and must never be merged:
// `updatePrefetchWindow` reaches *ahead* of the reader, `reportedProgressPage`
// reports only where the reader actually is.

/// Re-centres the prefetch window on the top-most visible page.
///
/// Deliberately given nothing but the page list, the visible set and the cache.
/// It holds no repository and no `lastSentPage`, so there is no path from
/// prefetching to a progress write even by accident — pages fetched ahead of
/// the reader cannot move their saved position.
///
/// Uses the *top-most* visible page rather than any other, matching what
/// `.scrollPosition` anchors to and what progress reports, so the window is
/// centred on the page the reader is looking at rather than one partly off the
/// bottom of the screen. Does nothing before the first layout, when nothing
/// has reported itself visible yet.
func updatePrefetchWindow(pageURLs: [URL], visiblePages: Set<Int>, cache: any PageImageCache) {
    guard let topMost = visiblePages.min() else { return }
    cache.setPrefetchWindow(pageURLs: pageURLs, currentIndex: topMost)
}

// MARK: - Reserving height for pages that are not showing an image
//
// The reader's content must be the same height whether or not its images
// happen to be in memory. Where that is not true, anything that rebuilds rows
// — the keyboard raised over the reader, a rotation, a memory warning, simply
// scrolling far enough for the byte budget to evict — changes the height of
// content *above* the reader, and the page they were looking at slides out
// from under them.

/// The height-to-width ratio reserved for a page in a chapter where nothing at
/// all has been decoded yet.
///
/// Measured rather than guessed: every page in the library as of 2026-08 is
/// 900px wide with a median height of 1549px. It is only ever the answer for
/// the first moments of a brand-new chapter — the first decode replaces it
/// with that chapter's own median — so being wrong for a differently-shaped
/// library costs one adjustment, not a persistent mis-sizing.
let defaultPageHeightRatio: CGFloat = 1549.0 / 900.0

/// The height to reserve for a page that is not currently rendering an image,
/// or `nil` before the first layout has established a width.
///
/// Answers in the order the reader can be most confident: this page's own
/// proportions if it has ever been decoded, otherwise what the rest of the
/// chapter looks like, otherwise the library-wide default. The point of the
/// first case is that it survives everything — the row being recycled and the
/// image being evicted both leave the ratio behind in the cache — so a page
/// seen once reserves its exact height forever after.
func reservedPageHeight(
    width: CGFloat,
    recordedHeightRatio: CGFloat?,
    chapterHeightRatio: CGFloat?
) -> CGFloat? {
    guard width > 0 else { return nil }
    let ratio = recordedHeightRatio ?? chapterHeightRatio ?? defaultPageHeightRatio
    guard ratio > 0 else { return nil }
    return width * ratio
}

/// The median of the height ratios known for a chapter, or `nil` when none of
/// its pages has been decoded yet.
///
/// The median rather than the mean because page heights in this library span
/// 8px to 2500px: a handful of full spreads or thin slices drags a mean well
/// away from what a typical page looks like, and the typical page is what an
/// undecoded row should be guessing at. It converges after a few pages and
/// then barely moves.
func medianHeightRatio(of ratios: [CGFloat]) -> CGFloat? {
    let sorted = ratios.filter { $0 > 0 }.sorted()
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

// MARK: - Where the selection's cancel badge goes
//
// The badge exists so a selection can be abandoned mid-drag with one continuous
// touch — drag into it and lift — which only works if it is on screen.

/// The cancel badge's frame, in the page's own coordinate space.
///
/// `visibleRect` is the part of the page the reader can actually see, in the
/// same coordinate space; `nil` — or a region that does not overlap the page at
/// all — falls back to the page's own bounds, reproducing exactly the behaviour
/// that was correct before zoom existed.
///
/// `topObstruction` is how much of the top of that visible region is covered by
/// something drawn over the reader. Selection mode forces the reader's controls
/// visible, and their bar is opaque material across the top, so without this the
/// badge would be placed correctly and still be invisible underneath it.
///
/// The result is always kept within the page, so a sliver of a page showing at
/// the edge of the screen cannot push the badge off it. Where the two cannot
/// both hold — a sliver narrower than the badge — staying on the page wins; a
/// reader is not selecting text on a 20pt strip of page.
func selectionCancelZoneFrame(
    displayFrameSize: CGSize,
    visibleRect: CGRect?,
    diameter: CGFloat,
    inset: CGFloat,
    topObstruction: CGFloat = 0
) -> CGRect {
    let pageBounds = CGRect(origin: .zero, size: displayFrameSize)

    var anchorRegion = pageBounds
    if let visibleRect {
        let overlap = visibleRect.intersection(pageBounds)
        if !overlap.isNull, !overlap.isEmpty {
            anchorRegion = overlap
        }
    }

    let maxOriginX = max(pageBounds.maxX - diameter, pageBounds.minX)
    let maxOriginY = max(pageBounds.maxY - diameter, pageBounds.minY)

    return CGRect(
        x: min(max(anchorRegion.maxX - diameter - inset, pageBounds.minX), maxOriginX),
        y: min(max(anchorRegion.minY + topObstruction + inset, pageBounds.minY), maxOriginY),
        width: diameter,
        height: diameter
    )
}

/// Whether the reader has scrolled `overscroll` points past the bottom of the
/// chapter — the shared inference behind both auto-advance (`overscroll` =
/// `pullThreshold`, a deliberate pull *past* the end) and read-detection
/// (`overscroll` = `-1`, merely reaching the end).
///
/// `isScrollDriven` means what it says: whether the offset this was handed was
/// produced by the reader rather than by a relayout. Zoom does not appear here
/// at all — it is a transform over the viewport, so it cannot move content
/// height — and the one place the two meet is at the auto-advance call site,
/// which additionally declines to fire while magnified as a product rule.
///
/// That question is the whole point of this function existing, and the
/// reason it takes the scroll phase rather than deriving everything from
/// geometry. The three geometry numbers describe where the content sits, not
/// how it got there, and the reader's content resizes on its own: pages outside
/// the prefetch window reserve 220pt instead of a real page's height, so
/// anything that recycles rows — most importantly the keyboard raised for the
/// result sheet's text field — collapses `contentHeight` under a stationary
/// reader. A large `contentOffsetY` left over from before the collapse then
/// clears any threshold, and the further into the chapter the reader was, the
/// more certainly it does. Requiring the scroll view to be under the reader's
/// finger is what separates the two.
///
/// Returns `false` for content no taller than the container: there is no bottom
/// to pass when everything already fits.
func readerPassedBottom(
    contentOffsetY: CGFloat,
    contentHeight: CGFloat,
    containerHeight: CGFloat,
    isScrollDriven: Bool,
    overscroll: CGFloat
) -> Bool {
    guard isScrollDriven else { return false }
    let maxScroll = contentHeight - containerHeight
    guard maxScroll > 0 else { return false }
    return contentOffsetY >= maxScroll + overscroll
}

/// The 1-based page the reader reports as its position: the chapter's last page
/// once the real bottom has been reached (so the backend can mark it `read`),
/// otherwise the top-most visible page — `visiblePages.min()`, which unlike
/// `.scrollPosition`'s reported value is reliable on a lazy stack of
/// unknown-height images.
///
/// `nil` before the first layout (empty set) → `sendProgress` ignores it.
func reportedProgressPage(visiblePages: Set<Int>, reachedEnd: Bool, pageCount: Int) -> Int? {
    reachedEnd ? pageCount : visiblePages.min().map { $0 + 1 }
}

/// The 0-based index the reader positions at when a chapter opens, or `nil`
/// when it has no saved position to return to and simply starts at the top.
///
/// The three ways a chapter can open, in the order they override one another:
/// an auto-advance restart forces the top, an explicit target page (a jump from
/// a 歷史紀錄 record — see `ReaderRoute.targetPage`) wins over the saved
/// position, and otherwise the chapter resumes where it was left. Page numbers
/// are 1-based and clamped, in case the chapter shrank since one was recorded.
///
/// Load-bearing for prefetching as well as scrolling: this is the page the
/// window is seeded at, which is why resuming mid-chapter is not slower than
/// starting from the beginning.
func readerStartIndex(
    pageCount: Int,
    restart: Bool,
    targetPage: Int?,
    lastReadPage: Int?
) -> Int? {
    guard pageCount > 0 else { return nil }

    func clamped(_ page: Int) -> Int {
        min(max(page - 1, 0), pageCount - 1)
    }

    if restart { return 0 }
    if let targetPage { return clamped(targetPage) }
    return lastReadPage.map(clamped)
}

/// A single reading page. `AuthorizedAsyncImage` (see `Shared/AuthorizedAsyncImage.swift`
/// — a stand-in for `AsyncImage` that attaches Cloudflare Access headers)
/// provides the real loading state deferred in M3. Because it has no
/// built-in retry, a failed page would stay failed forever, so the failure
/// placeholder is tappable: tapping bumps `reloadToken`, which re-keys the
/// view so it re-issues the request.
private struct ReaderPage: View {
    let url: URL
    /// This page's 1-based position within the chapter. Travels out with a
    /// produced crop (see `CroppedSelection.pageNumber`) because the reader,
    /// not this page, presents the confirmation sheet.
    let pageNumber: Int
    /// Shared token from the reader. A change re-requests this page only when it
    /// is currently failed.
    let retryAllToken: Int
    /// Whether the Reader is in text-selection mode. Drives whether this page
    /// installs the drag-to-select overlay/gesture over its rendered image.
    let isSelecting: Bool
    /// How much of the top of the reader the control bar covers. Selection mode
    /// forces the controls visible, so the cancel badge is placed below this.
    let controlBarHeight: CGFloat
    /// The reader's settled magnification and how far its viewport is moved,
    /// which together say which part of this page is on screen.
    ///
    /// The *settled* scale rather than the live one, deliberately: a pinch in
    /// flight would otherwise invalidate every realised row on every frame, and
    /// panning is disabled while selecting, so the badge only has to be right
    /// once the fingers are off.
    let magnification: CGFloat
    let viewportPan: CGSize
    /// The width this page is laid out at, measured by the reader. `0` before
    /// the first layout, which means no height can be reserved yet.
    let reservedWidth: CGFloat
    /// The chapter's median height ratio, used when *this* page has never been
    /// decoded and so has no proportions of its own on record.
    let chapterHeightRatio: CGFloat?
    /// Tapping any failed page's retry button reloads every failed page at once
    /// (bumps the shared `retryAllToken` in the parent).
    let onRetryAll: () -> Void
    /// Reports this page entering (`true`) / leaving (`false`) the viewport, so
    /// the reader can track the top-most visible page for progress reporting.
    let onVisible: (Bool) -> Void
    /// Hands a finished crop up to the reader, which owns the confirmation
    /// sheet. Reported rather than presented here: this view lives inside a
    /// `LazyVStack` and is destroyed when it scrolls out of the viewport, so a
    /// sheet bound to its `@State` dies with it — which is exactly what used to
    /// happen when the keyboard shrank the viewport and closed the sheet out
    /// from under the reader mid-edit.
    let onCrop: (CroppedSelection) -> Void
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
    /// `selectionCancelZoneFrame`), so the badge can visually confirm "release
    /// here to cancel" before the finger lifts.
    @State private var isHoveringCancelZone = false
    /// Read for this row alone — this page's own recorded proportions — the
    /// way `AuthorizedAsyncImage` reads the same cache for the image it draws.
    /// The reader holds the same environment value for different questions
    /// (the prefetch window, and this chapter's median), which are its
    /// business rather than a row's.
    @Environment(\.pageImageCache) private var pageImageCache

    /// Fixed-size "release here to cancel" zone, so cancelling is possible
    /// mid-drag with a single continuous touch: drag into the badge and lift,
    /// instead of drawing a selection and confirming it. See `ocr-recognition`
    /// ticket 03's cancel requirement.
    ///
    /// Where it sits is `selectionCancelZoneFrame`'s business — the top-right of
    /// the *visible* part of the page rather than of the page itself, since a
    /// magnified page is far larger than the screen.
    private let cancelZoneDiameter: CGFloat = 44
    /// How far the badge is held off the edges of the visible region.
    private let cancelZoneInset: CGFloat = 12

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
                                    selectionOverlay(
                                        displayFrameSize: proxy.size,
                                        // What of this page the reader can
                                        // actually see. At full width that is
                                        // the whole viewport; magnified it is
                                        // the 1/s band the transform puts on
                                        // screen, which the scroll view knows
                                        // nothing about — it is unmagnified at
                                        // every scale — so it has to be derived
                                        // rather than looked up.
                                        visibleRect: proxy.bounds(of: .scrollView).map {
                                            ReaderZoom.visibleRegion(
                                                inViewport: $0,
                                                scale: magnification,
                                                pan: viewportPan
                                            )
                                        }
                                    )
                                }
                            }
                        }
                case .empty:
                    loadingPlaceholder
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

    }

    // MARK: - Selection

    private func dragRect(_ value: DragGesture.Value) -> CGRect {
        CGRect(
            x: value.startLocation.x,
            y: value.startLocation.y,
            width: value.translation.width,
            height: value.translation.height
        ).standardized
    }

    private func selectionOverlay(displayFrameSize: CGSize, visibleRect: CGRect?) -> some View {
        let cancelZone = selectionCancelZoneFrame(
            displayFrameSize: displayFrameSize,
            visibleRect: visibleRect,
            diameter: cancelZoneDiameter,
            inset: cancelZoneInset,
            topObstruction: controlBarHeight
        )
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
        onCrop(
            CroppedSelection(image: UIImage(cgImage: croppedCGImage), pageNumber: pageNumber)
        )
    }

    /// Stands in for the image at as close to its real height as is known, so
    /// this row occupies the same space whether or not its image is in memory.
    ///
    /// This is the whole of the fix for the reader's content shifting: a row
    /// that shrinks to a token height while it has no image changes the height
    /// of everything above the reader, and the page they were looking at moves.
    /// Falls back to the old fixed height only before the first layout, when
    /// there is no width to reserve against.
    @ViewBuilder
    private var loadingPlaceholder: some View {
        let reserved = reservedPageHeight(
            width: reservedWidth,
            recordedHeightRatio: pageImageCache.heightRatio(for: url),
            chapterHeightRatio: chapterHeightRatio
        )
        if let reserved {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: reserved)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    /// Deliberately *not* height-reserved, unlike `loadingPlaceholder`. A
    /// failed page is a dead end the reader has to act on, and stranding its
    /// retry button in the middle of a screen-and-a-half of blank space serves
    /// nobody. The shift when a retry succeeds is one the reader asked for.
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
