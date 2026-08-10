//
//  ReaderPrefetchWindowTests.swift
//  vista_comicTests
//
//  Coverage for `reader-page-prefetch` ticket 02 at the *reader* level: where
//  the window is seeded when a chapter opens, how it slides as the reader
//  scrolls, and — the one that matters most — that none of it can move the
//  reader's saved position.
//
//  Exercises the reader's window logic through a substituted cache rather than
//  by rendering the reader, following how `SelectionEnqueueFlowTests` and
//  `HistoryActionsTests` drive reader-owned logic with test doubles. The three
//  functions under test are free functions in `ComicView.swift` precisely so
//  this is possible.
//

import Foundation
import Testing
import UIKit

@testable import vista_comic

/// Records the windows it is told to prefetch, and nothing else.
///
/// Note what it *cannot* do: `setPrefetchWindow` returns nothing and takes no
/// callback, so there is no channel by which prefetching could report a page
/// back to the reader and have it counted as read.
private final class RecordingPageImageCache: PageImageCache, @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [(pageURLs: [URL], currentIndex: Int)] = []

    func cachedImage(for url: URL) -> UIImage? { nil }

    func image(for url: URL) async throws -> UIImage { UIImage() }

    func setPrefetchWindow(pageURLs: [URL], currentIndex: Int) {
        lock.withLock { windows.append((pageURLs, currentIndex)) }
    }

    func heightRatio(for url: URL) -> CGFloat? { nil }

    var windowCount: Int {
        lock.withLock { windows.count }
    }

    var lastWindow: (pageURLs: [URL], currentIndex: Int)? {
        lock.withLock { windows.last }
    }

    /// The URLs the most recent window actually covers, in request order.
    var lastWindowURLs: [URL] {
        guard let last = lastWindow else { return [] }
        return PagePrefetchWindow.urls(in: last.pageURLs, centredOn: last.currentIndex)
    }
}

private func chapterURLs(_ count: Int, chapter: String = "one") -> [URL] {
    (0..<count).map {
        URL(string: "https://api.example.com/media/comic/\(chapter)/\($0)")!
    }
}

@Suite("Reader prefetch window")
struct ReaderPrefetchWindowTests {

    // MARK: - Sliding with the reader

    /// The top-most visible page, matching what `.scrollPosition` anchors to —
    /// not a page hanging half off the bottom of the screen.
    @Test func theWindowIsCentredOnTheTopMostVisiblePage() {
        let urls = chapterURLs(40)
        let cache = RecordingPageImageCache()

        updatePrefetchWindow(pageURLs: urls, visiblePages: [4, 5, 6], cache: cache)

        #expect(cache.lastWindow?.currentIndex == 4)
    }

    @Test func theWindowSlidesAsTheReaderScrolls() {
        let urls = chapterURLs(40)
        let cache = RecordingPageImageCache()

        updatePrefetchWindow(pageURLs: urls, visiblePages: [0, 1], cache: cache)
        updatePrefetchWindow(pageURLs: urls, visiblePages: [7, 8], cache: cache)

        #expect(cache.windowCount == 2)
        #expect(cache.lastWindow?.currentIndex == 7)
        #expect(cache.lastWindowURLs.contains(urls[12]))
        // Two behind travels with the reader; anything further back is dropped.
        #expect(cache.lastWindowURLs.contains(urls[5]))
        #expect(!cache.lastWindowURLs.contains(urls[4]))
    }

    /// Before the first layout nothing has reported itself visible, and a
    /// window centred on a guess would fetch pages the reader may never see.
    @Test func nothingIsPrefetchedBeforeAnyPageReportsItselfVisible() {
        let cache = RecordingPageImageCache()

        updatePrefetchWindow(pageURLs: chapterURLs(40), visiblePages: [], cache: cache)

        #expect(cache.windowCount == 0)
    }

    /// A chapter change re-seeds the window on the new chapter's pages. The
    /// cache is never told to discard anything — there is no such message —
    /// which is what keeps flipping to an adjacent chapter and back instant.
    @Test func aChapterChangeReSeedsTheWindowOnTheNewChaptersPages() {
        let previous = chapterURLs(20, chapter: "previous")
        let next = chapterURLs(20, chapter: "next")
        let cache = RecordingPageImageCache()

        updatePrefetchWindow(pageURLs: previous, visiblePages: [10], cache: cache)
        updatePrefetchWindow(pageURLs: next, visiblePages: [0], cache: cache)

        #expect(cache.lastWindow?.pageURLs == next)
        #expect(cache.lastWindowURLs.allSatisfy { next.contains($0) })
    }

    // MARK: - Prefetching versus progress

    /// The failure this feature could most damage the user with: a page fetched
    /// ahead of the reader being written back as their position, silently
    /// moving their saved place across the whole library.
    ///
    /// Both signals are derived here from the *same* visible set, which is the
    /// only input they share. The window reaches five pages past the reader
    /// while the reported position stays exactly where the reader is.
    @Test func prefetchingReachesAheadOfTheReaderWithoutMovingTheirPosition() {
        let urls = chapterURLs(40)
        let cache = RecordingPageImageCache()
        let visible: Set<Int> = [2, 3]

        updatePrefetchWindow(pageURLs: urls, visiblePages: visible, cache: cache)

        // Fetched ahead: pages 4 through 8 (1-based) are in hand already.
        #expect(cache.lastWindowURLs.contains(urls[7]))
        // Reported as read: page 3, and nothing further along.
        #expect(reportedProgressPage(visiblePages: visible, reachedEnd: false, pageCount: 40) == 3)
    }

    /// Re-centring the window repeatedly — a fast scroll — leaves the reported
    /// position untouched, because it is derived from visibility alone and the
    /// window has no way to report back.
    @Test func repeatedWindowUpdatesLeaveTheReportedPageAlone() {
        let urls = chapterURLs(40)
        let cache = RecordingPageImageCache()
        let visible: Set<Int> = [5]

        for _ in 0..<10 {
            updatePrefetchWindow(pageURLs: urls, visiblePages: visible, cache: cache)
        }

        #expect(cache.windowCount == 10)
        #expect(reportedProgressPage(visiblePages: visible, reachedEnd: false, pageCount: 40) == 6)
    }

    /// Reaching the real bottom is the one thing that reports past the top-most
    /// visible page — and it is the reader arriving there, never a prefetch.
    @Test func reachingTheEndReportsTheLastPage() {
        #expect(reportedProgressPage(visiblePages: [30], reachedEnd: true, pageCount: 40) == 40)
        #expect(reportedProgressPage(visiblePages: [], reachedEnd: false, pageCount: 40) == nil)
    }

    // MARK: - Where the window is seeded when a chapter opens

    @Test func resumingMidChapterSeedsAtTheResumePositionNotTheFirstPage() {
        let index = readerStartIndex(
            pageCount: 40, restart: false, targetPage: nil, lastReadPage: 18
        )

        #expect(index == 17)
    }

    @Test func aHistoryJumpsTargetPageWinsOverTheSavedPosition() {
        let index = readerStartIndex(
            pageCount: 40, restart: false, targetPage: 25, lastReadPage: 18
        )

        #expect(index == 24)
    }

    /// Auto-advancing past the end of a chapter opens the next one at the top,
    /// ignoring whatever position it may have been left at before.
    @Test func anAutoAdvanceRestartSeedsAtTheFirstPage() {
        let index = readerStartIndex(
            pageCount: 40, restart: true, targetPage: 25, lastReadPage: 18
        )

        #expect(index == 0)
    }

    /// `nil` means "no saved position", which the reader treats as the top —
    /// and which it must keep meaning, because it is also what stops the resume
    /// position being re-sent to the backend on open.
    @Test func aChapterWithNoSavedPositionHasNoStartIndex() {
        #expect(readerStartIndex(pageCount: 40, restart: false, targetPage: nil, lastReadPage: nil) == nil)
    }

    /// A recorded page number can outlive the chapter it was recorded for.
    @Test func aStartPageBeyondTheChaptersEndIsClamped() {
        #expect(readerStartIndex(pageCount: 10, restart: false, targetPage: nil, lastReadPage: 99) == 9)
        #expect(readerStartIndex(pageCount: 10, restart: false, targetPage: 99, lastReadPage: nil) == 9)
        #expect(readerStartIndex(pageCount: 10, restart: false, targetPage: 0, lastReadPage: nil) == 0)
    }

    @Test func anEmptyChapterHasNoStartIndex() {
        #expect(readerStartIndex(pageCount: 0, restart: true, targetPage: 3, lastReadPage: 3) == nil)
        #expect(readerStartIndex(pageCount: 0, restart: false, targetPage: nil, lastReadPage: 3) == nil)
    }

    // MARK: - The window's shape

    /// Order is not cosmetic: the window is wider than the number of fetches
    /// allowed to run at once, so whatever is last in this list is what waits.
    @Test func theWindowAsksForTheReadersOwnPageFirstThenAheadThenBehind() {
        let urls = chapterURLs(40)

        let window = PagePrefetchWindow.urls(in: urls, centredOn: 10)

        #expect(window == [
            urls[10], urls[11], urls[12], urls[13], urls[14], urls[15],
            urls[9], urls[8],
        ])
    }

    @Test func theWindowClampsAtBothEndsOfAChapter() {
        let urls = chapterURLs(10)

        #expect(PagePrefetchWindow.urls(in: urls, centredOn: 0)
            == [urls[0], urls[1], urls[2], urls[3], urls[4], urls[5]])
        #expect(PagePrefetchWindow.urls(in: urls, centredOn: 9)
            == [urls[9], urls[8], urls[7]])
        #expect(PagePrefetchWindow.urls(in: [], centredOn: 0).isEmpty)
    }

    /// An index the chapter cannot contain must not crash the reader; a page
    /// list can shrink under a recorded position.
    @Test func anOutOfRangeCentreIsClampedIntoTheChapter() {
        let urls = chapterURLs(10)

        #expect(PagePrefetchWindow.urls(in: urls, centredOn: 99).first == urls[9])
        #expect(PagePrefetchWindow.urls(in: urls, centredOn: -5).first == urls[0])
    }
}
