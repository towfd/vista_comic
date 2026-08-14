//
//  SelectionCancelZoneTests.swift
//  vista_comicTests
//
//  Coverage for `reader-zoom` ticket 02: the "drag here and release to cancel"
//  badge has to stay reachable at every magnification.
//
//  The badge is only useful mid-drag — drag into it and lift, without ever
//  raising the finger — so being off screen does not merely make it awkward,
//  it removes the only way to abandon a selection in progress. Anchoring it to
//  the page's own top-right corner was correct while a page was always exactly
//  screen-width; at 3x that corner is two screen widths to the right, and on a
//  tall page several screens above.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Selection cancel zone")
struct SelectionCancelZoneTests {

    /// A page at 3x on a 393pt phone, and the window onto it.
    private let magnifiedPage = CGSize(width: 1179, height: 4000)
    private let diameter: CGFloat = 44
    private let inset: CGFloat = 12

    /// What the reader's own top control bar covers, which selection mode
    /// always has on screen.
    private let controlBar: CGFloat = 46

    private func frame(
        visible: CGRect?,
        page: CGSize? = nil,
        topObstruction: CGFloat = 0
    ) -> CGRect {
        selectionCancelZoneFrame(
            displayFrameSize: page ?? magnifiedPage,
            visibleRect: visible,
            diameter: diameter,
            inset: inset,
            topObstruction: topObstruction
        )
    }

    @Test("With no visible region known, the badge sits where it always did")
    func unknownVisibleRegionKeepsTheOriginalCorner() {
        // Pins the pre-zoom behaviour: this is what every unmagnified page got,
        // and must keep getting.
        let page = CGSize(width: 393, height: 640)
        #expect(
            frame(visible: nil, page: page)
                == CGRect(x: 393 - 44 - 12, y: 12, width: 44, height: 44)
        )
    }

    @Test("Magnified, the badge follows the visible part of the page")
    func badgeFollowsTheVisibleRegion() {
        // The reader is panned to the left edge and scrolled well down a page
        // that is now several screens tall.
        let visible = CGRect(x: 0, y: 1500, width: 393, height: 800)
        #expect(frame(visible: visible) == CGRect(x: 337, y: 1512, width: 44, height: 44))
    }

    @Test("The badge tracks the top of what is visible, not the top of the page")
    func badgeDoesNotStayAtThePageTop() {
        // The failure this guards against is vertical as much as horizontal: at
        // 3x a page is several screens tall, so a badge pinned to the page's top
        // is off screen whenever the reader is looking at the middle of it.
        let visible = CGRect(x: 0, y: 1500, width: 393, height: 800)
        let result = frame(visible: visible)
        #expect(result.minY > visible.minY)
        #expect(result.maxY < visible.maxY)
    }

    @Test("Panned to the right edge, the badge is at the page's own corner")
    func badgeAtTheRightEdgeMatchesThePageCorner() {
        let visible = CGRect(x: 786, y: 0, width: 393, height: 800)
        #expect(frame(visible: visible).maxX == magnifiedPage.width - inset)
    }

    @Test("A visible region larger than the page is the same as not knowing one")
    func anOversizedVisibleRegionClampsToThePage() {
        let oversized = CGRect(x: -200, y: -200, width: 4000, height: 9000)
        #expect(frame(visible: oversized) == frame(visible: nil))
    }

    @Test("A visible region that misses the page entirely falls back to the page")
    func aNonOverlappingVisibleRegionFallsBack() {
        // Can happen transiently while rows are being recycled; the badge must
        // still be somewhere sensible rather than at a wild coordinate.
        let elsewhere = CGRect(x: 9000, y: 9000, width: 393, height: 800)
        #expect(frame(visible: elsewhere) == frame(visible: nil))
    }

    @Test("A sliver of a page showing cannot push the badge off it")
    func badgeStaysWithinThePage() {
        let sliver = CGRect(x: 0, y: 0, width: 20, height: 800)
        let result = frame(visible: sliver)
        let pageBounds = CGRect(origin: .zero, size: magnifiedPage)
        #expect(pageBounds.contains(result))
    }

    @Test("The badge clears the reader's own control bar")
    func badgeSitsBelowTheControlBar() {
        // Selection mode forces the controls visible, and their bar is opaque
        // material across the top of the reader. Placed at the visible region's
        // own top the badge is positioned correctly and still cannot be seen,
        // which is a different failure from being off screen and just as bad.
        let visible = CGRect(x: 0, y: 1500, width: 393, height: 800)
        let result = frame(visible: visible, topObstruction: controlBar)
        #expect(result.minY >= visible.minY + controlBar)
    }

    @Test("With nothing covering the reader the badge sits at the top as before")
    func noObstructionLeavesTheBadgeAtTheTop() {
        let visible = CGRect(x: 0, y: 1500, width: 393, height: 800)
        #expect(frame(visible: visible, topObstruction: 0).minY == visible.minY + inset)
    }

    @Test("The badge is visible wherever the reader has panned, at either magnification")
    func badgeIsAlwaysReachable() {
        // The property the whole function exists for, checked across the pan
        // range and at both magnifications rather than at one convenient spot.
        // "Visible" here means inside the viewport *and* below the control bar,
        // since the two failures it can have are being off screen and being
        // underneath something.
        let viewport = CGSize(width: 393, height: 800)
        for page in [CGSize(width: 786, height: 2670), magnifiedPage] {
            for x in stride(from: CGFloat(0), through: page.width - viewport.width, by: 131) {
                for y in stride(from: CGFloat(0), through: page.height - viewport.height, by: 400) {
                    let visible = CGRect(origin: CGPoint(x: x, y: y), size: viewport)
                    let result = frame(visible: visible, page: page, topObstruction: controlBar)
                    #expect(visible.contains(result), "off screen at \(page) pan (\(x), \(y))")
                    #expect(
                        result.minY >= visible.minY + controlBar,
                        "under the control bar at \(page) pan (\(x), \(y))"
                    )
                }
            }
        }
    }
}
