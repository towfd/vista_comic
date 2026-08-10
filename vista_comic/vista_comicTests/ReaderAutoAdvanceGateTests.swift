//
//  ReaderAutoAdvanceGateTests.swift
//  vista_comicTests
//
//  Coverage for `reader-auto-advance-false-trigger` ticket 01: the reader must
//  not treat a shrinking content height as a pull past the end of a chapter.
//
//  The bug these exist for is not subtle in its effect — correcting recognized
//  text mid-chapter on an iPad ran the reader to the last chapter of the comic —
//  but it is entirely invisible to a test that only checks the arithmetic,
//  because the arithmetic was never wrong. What was missing was the question of
//  whether the reader was touching the scroll view at all. So the cases below
//  are organised around that: same geometry, different answer depending on
//  whether the offset was produced by a finger or by a relayout.
//
//  `readerPassedBottom` is a free function in `ComicView.swift` for the same
//  reason `readerStartIndex` and `reportedProgressPage` are — so the reader's
//  inferences can be exercised without rendering the reader.
//

import Foundation
import Testing

@testable import vista_comic

/// The reader's real overscroll requirement, so these read against the shipped
/// value rather than a number invented here.
private let pullThreshold: CGFloat = 120

/// What a mid-chapter reader looks like on an iPad before anything collapses:
/// thirty pages at roughly 1400pt, parked around page fifteen.
private let containerHeight: CGFloat = 1300
private let fullContentHeight: CGFloat = 30 * 1400
private let midChapterOffset: CGFloat = 15 * 1400

/// The same chapter after row recycling drops every page outside the prefetch
/// window back to its 220pt placeholder. Nothing scrolled; the content simply
/// got shorter underneath the reader.
private let collapsedContentHeight: CGFloat = 30 * 220

@Suite("Reader auto-advance gate")
struct ReaderAutoAdvanceGateTests {

    // MARK: - The reported bug

    @Test("A content collapse under a stationary reader is not a pull past the end")
    func collapseWhileIdleIsNotAPull() {
        // The offset alone clears the collapsed bottom by a wide margin — this
        // is precisely the state that used to advance the chapter.
        #expect(midChapterOffset > collapsedContentHeight - containerHeight + pullThreshold)

        #expect(
            readerPassedBottom(
                contentOffsetY: midChapterOffset,
                contentHeight: collapsedContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: false,
                overscroll: pullThreshold
            ) == false
        )
    }

    @Test("A content collapse under a stationary reader does not mark the chapter read")
    func collapseWhileIdleIsNotTheBottom() {
        #expect(
            readerPassedBottom(
                contentOffsetY: midChapterOffset,
                contentHeight: collapsedContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: false,
                overscroll: -1
            ) == false
        )
    }

    @Test("Near the top of a chapter a collapse was harmless even before the gate")
    func collapseNearTheTopIsNotAPull() {
        // Matches the device report: selecting near the top never misbehaved,
        // because the stale offset was too small to clear the collapsed bottom.
        // Worth pinning — it is the observation that identified the mechanism.
        let nearTopOffset: CGFloat = 400
        #expect(nearTopOffset < collapsedContentHeight - containerHeight + pullThreshold)

        #expect(
            readerPassedBottom(
                contentOffsetY: nearTopOffset,
                contentHeight: collapsedContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: false,
                overscroll: pullThreshold
            ) == false
        )
    }

    // MARK: - What must still work

    @Test("Pulling past the bottom still advances")
    func pullPastBottomStillCounts() {
        let maxScroll = fullContentHeight - containerHeight

        #expect(
            readerPassedBottom(
                contentOffsetY: maxScroll + pullThreshold,
                contentHeight: fullContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: pullThreshold
            )
        )
    }

    @Test("Reaching the bottom without pulling past it does not advance")
    func reachingTheBottomIsNotAPull() {
        let maxScroll = fullContentHeight - containerHeight

        #expect(
            readerPassedBottom(
                contentOffsetY: maxScroll,
                contentHeight: fullContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: pullThreshold
            ) == false
        )
    }

    @Test("Reaching the bottom does mark the chapter read")
    func reachingTheBottomIsTheBottom() {
        let maxScroll = fullContentHeight - containerHeight

        #expect(
            readerPassedBottom(
                contentOffsetY: maxScroll,
                contentHeight: fullContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: -1
            )
        )
    }

    @Test("Content shorter than the screen has no bottom to pass")
    func contentThatFitsHasNoBottom() {
        #expect(
            readerPassedBottom(
                contentOffsetY: 0,
                contentHeight: 500,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: pullThreshold
            ) == false
        )
    }

    @Test("Content shorter than the screen is not reported as read either")
    func contentThatFitsIsNotTheBottom() {
        // Guards the arithmetic as much as the behaviour: with a negative
        // `maxScroll` and `overscroll` of -1, an offset of 0 would otherwise
        // clear the comparison and mark a one-page chapter read on sight.
        #expect(
            readerPassedBottom(
                contentOffsetY: 0,
                contentHeight: 500,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: -1
            ) == false
        )
    }
}
