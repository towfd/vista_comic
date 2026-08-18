//
//  ReaderZoomTests.swift
//  vista_comicTests
//
//  Coverage for `reader-zoom` ticket 01.
//
//  Zoom is an absolute transform over the viewport and the layout never
//  changes, so the arithmetic under test here is entirely about *rendering*:
//  what scale is shown, how far the magnified strip may be moved, and where a
//  focal point ends up. None of it reads content size for the purpose of
//  correcting a layout change, because there is no layout change.
//
//  That is also why there is no arming state machine left to test. The previous
//  model needed one because committing a new layout width moved content height
//  by up to 3x and the bottom-edge inference reads content height. A transform
//  cannot move content height, so the inference needs nothing but the
//  scroll-driven discipline it already had — covered by
//  `ReaderAutoAdvanceGateTests`, unchanged.
//
//  The rendering model these tests are written against, for one axis:
//
//      screen(y) = length/2 + scale × (y − length/2) + pan
//
//  where `y` is a point in the untransformed viewport.
//

import Foundation
import SwiftUI
import Testing

@testable import vista_comic

/// Where an untransformed viewport point is drawn, given a scale and a pan.
private func screenPosition(
    of viewportPoint: CGFloat,
    containerLength: CGFloat,
    scale: CGFloat,
    pan: CGFloat
) -> CGFloat {
    let middle = containerLength / 2
    return middle + scale * (viewportPoint - middle) + pan
}

private func isClose(_ lhs: CGFloat, _ rhs: CGFloat, within tolerance: CGFloat = 0.0001) -> Bool {
    abs(lhs - rhs) < tolerance
}

@Suite("Reader zoom scale")
struct ReaderZoomScaleTests {

    @Test("A scale inside the bounds is left alone")
    func scaleInsideBoundsIsUnchanged() {
        #expect(ReaderZoom.clamped(1.0) == 1.0)
        #expect(ReaderZoom.clamped(2.0) == 2.0)
        #expect(ReaderZoom.clamped(3.0) == 3.0)
    }

    @Test("Pinching in past full width settles at full width")
    func scaleBelowMinimumClamps() {
        #expect(ReaderZoom.clamped(0.4) == ReaderZoom.minScale)
        #expect(ReaderZoom.minScale == 1.0)
    }

    @Test("Pinching out past the ceiling settles at the ceiling")
    func scaleAboveMaximumClamps() {
        #expect(ReaderZoom.clamped(7.5) == ReaderZoom.maxScale)
        #expect(ReaderZoom.maxScale == 3.0)
    }

    @Test("A scale just above full width settles at exactly full width")
    func nearlyFullWidthSnaps() {
        // Load-bearing rather than cosmetic: auto-advance is inert whenever the
        // scale is not exactly full width, so stopping at 1.03 would silently
        // cost the reader the next chapter.
        #expect(ReaderZoom.settled(1.03) == ReaderZoom.minScale)
        #expect(ReaderZoom.settled(1.0) == ReaderZoom.minScale)
        #expect(ReaderZoom.settled(0.4) == ReaderZoom.minScale)
    }

    @Test("A scale clear of full width keeps its value")
    func magnifiedScaleSettlesWhereItIs() {
        #expect(ReaderZoom.settled(1.5) == 1.5)
        #expect(ReaderZoom.settled(2.4) == 2.4)
        #expect(ReaderZoom.settled(7.5) == ReaderZoom.maxScale)
    }

    @Test("The rendered scale is never below full width, however hard the reader pinches in")
    func rubberBandNeverShrinksTheViewport() {
        // The defect this replaces: the previous model expressed the live
        // transform as a ratio against a committed layout, so it went below 1
        // for the whole of every zoom-out gesture and drew the reader smaller
        // than the screen.
        #expect(ReaderZoom.rubberBanded(0.5) == ReaderZoom.minScale)
        #expect(ReaderZoom.rubberBanded(0.001) == ReaderZoom.minScale)
        #expect(ReaderZoom.rubberBanded(0) == ReaderZoom.minScale)
        #expect(ReaderZoom.rubberBanded(-2) == ReaderZoom.minScale)
    }

    @Test("Overshooting the ceiling is damped but still shown")
    func rubberBandResistsAboveTheCeiling() {
        let over = ReaderZoom.rubberBanded(4.0)
        #expect(over > ReaderZoom.maxScale)
        #expect(over < 4.0)
    }

    @Test("Inside the bounds the gesture is not damped at all")
    func rubberBandPassesThroughInsideTheBounds() {
        #expect(ReaderZoom.rubberBanded(1.0) == 1.0)
        #expect(ReaderZoom.rubberBanded(2.4) == 2.4)
        #expect(ReaderZoom.rubberBanded(3.0) == 3.0)
    }
}

@Suite("Panning a magnified strip")
struct ReaderZoomPanTests {

    private let width: CGFloat = 400

    @Test("At full width there is nothing to pan")
    func noSlackAtFullWidth() {
        #expect(ReaderZoom.panLimit(containerLength: width, scale: 1.0) == 0)
        #expect(ReaderZoom.clampedPan(120, containerLength: width, scale: 1.0) == 0)
    }

    @Test("The pan reaches exactly as far as the magnified content does")
    func slackMatchesTheHiddenContent() {
        // At scale s the content extends containerLength × (s − 1) / 2 past
        // each edge, and that is precisely how far the pan has to reach.
        #expect(ReaderZoom.panLimit(containerLength: width, scale: 2.0) == 200)
        #expect(ReaderZoom.panLimit(containerLength: width, scale: 3.0) == 400)
    }

    @Test("Panning stops at the edge of the page rather than pulling in background")
    func panIsHeldInsideTheContent() {
        #expect(ReaderZoom.clampedPan(9_999, containerLength: width, scale: 3.0) == 400)
        #expect(ReaderZoom.clampedPan(-9_999, containerLength: width, scale: 3.0) == -400)
        #expect(ReaderZoom.clampedPan(120, containerLength: width, scale: 3.0) == 120)
    }

    @Test("Panning to the limit puts the page's own edge on the screen's edge")
    func theLimitIsExactlyTheEdge() {
        // Asserted as the property rather than as a number: at full pan the
        // untransformed viewport's left edge should land on the screen's left
        // edge, which is what "you can see the whole page" means.
        let scale: CGFloat = 3
        let limit = ReaderZoom.panLimit(containerLength: width, scale: scale)
        let leftEdge = screenPosition(of: 0, containerLength: width, scale: scale, pan: limit)
        #expect(isClose(leftEdge, 0))
    }

    @Test("A scale change keeps what is under the fingers under the fingers")
    func focalPointStaysPut() {
        // The property the whole pan correction exists for. Unlike the model it
        // replaces, this reads nothing about content size — so there is no
        // stale measurement available for it to be wrong about.
        for focal in [CGFloat(0), 0.25, 0.5, 0.8, 1.0] {
            for (from, to) in [(CGFloat(1), CGFloat(3)), (3, 1), (1.5, 2.2), (2.2, 1.5)] {
                let previousPan: CGFloat = from == 1 ? 0 : 40
                let focalScreenPoint = focal * width

                let source = ((focalScreenPoint - width / 2 - previousPan) / from) + width / 2
                let corrected = ReaderZoom.panKeepingFocalPoint(
                    focal: focal,
                    containerLength: width,
                    previousPan: previousPan,
                    from: from,
                    to: to
                )

                #expect(isClose(
                    screenPosition(of: source, containerLength: width, scale: to, pan: corrected),
                    focalScreenPoint
                ))
            }
        }
    }

    @Test("Pinching at the centre needs no pan at all")
    func centredPinchDoesNotPan() {
        let corrected = ReaderZoom.panKeepingFocalPoint(
            focal: 0.5, containerLength: width, previousPan: 0, from: 1, to: 3
        )
        #expect(isClose(corrected, 0))
    }

    @Test("A container that has not been measured yet is left alone")
    func unmeasuredContainerIsInert() {
        #expect(ReaderZoom.panLimit(containerLength: 0, scale: 3) == 0)
        #expect(ReaderZoom.panKeepingFocalPoint(
            focal: 0.5, containerLength: 0, previousPan: 12, from: 1, to: 3
        ) == 12)
    }
}

@Suite("Reaching the ends of a magnified chapter")
struct ReaderZoomEndReachTests {

    private let containerHeight: CGFloat = 800
    private let contentHeight: CGFloat = 30_000

    private func pan(at offset: CGFloat, scale: CGFloat = 3) -> CGFloat {
        ReaderZoom.endOfChapterPan(
            scrollOffset: offset,
            contentHeight: contentHeight,
            containerHeight: containerHeight,
            scale: scale
        )
    }

    @Test("At full width there is no shift, anywhere in the chapter")
    func inertAtFullWidth() {
        #expect(pan(at: 0, scale: 1) == 0)
        #expect(pan(at: 15_000, scale: 1) == 0)
        #expect(pan(at: 29_200, scale: 1) == 0)
    }

    @Test("In the middle of a chapter the scroll view is left to do all the work")
    func noShiftMidChapter() {
        #expect(pan(at: 15_000) == 0)
    }

    @Test("At the top the chapter's first screen is brought fully into view")
    func topOfChapterIsReachable() {
        // Without this the outermost band of the first screen can never be
        // scrolled into the magnified view, because there is no scrolling left
        // to do it with.
        let shift = pan(at: 0)
        #expect(shift == ReaderZoom.panLimit(containerLength: containerHeight, scale: 3))
        let contentTop = screenPosition(
            of: 0, containerLength: containerHeight, scale: 3, pan: shift
        )
        #expect(isClose(contentTop, 0))
    }

    @Test("At the bottom the chapter's last screen is brought fully into view")
    func bottomOfChapterIsReachable() {
        let shift = pan(at: contentHeight - containerHeight)
        #expect(shift == -ReaderZoom.panLimit(containerLength: containerHeight, scale: 3))
        let contentBottom = screenPosition(
            of: containerHeight, containerLength: containerHeight, scale: 3, pan: shift
        )
        #expect(isClose(contentBottom, containerHeight))
    }

    @Test("The shift decays as scrolling takes over, rather than snapping away")
    func shiftDecaysSmoothly() {
        // A discontinuity here would be a visible jolt as the reader leaves the
        // top of a chapter, which is exactly the class of defect this feature
        // was rewritten to remove.
        let samples = stride(from: CGFloat(0), through: 2_000, by: 50).map { pan(at: $0) }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later <= earlier)
            #expect(earlier - later < ReaderZoom.panLimit(containerLength: containerHeight, scale: 3))
        }
        #expect(samples.last == 0)
    }

    @Test("A chapter shorter than the screen is simply centred")
    func shortChapterIsCentred() {
        #expect(ReaderZoom.endOfChapterPan(
            scrollOffset: 0, contentHeight: 500, containerHeight: containerHeight, scale: 3
        ) == 0)
    }

    @Test("A scroll offset outside the chapter is treated as its nearest end")
    func overscrollIsTreatedAsTheEnd() {
        #expect(pan(at: -200) == pan(at: 0))
        #expect(pan(at: contentHeight) == pan(at: contentHeight - containerHeight))
    }
}

@Suite("What the reader can actually see")
struct ReaderZoomVisibleRegionTests {

    /// A 400x800 window, in the coordinate space of a page whose top sits
    /// 300pt above the top of that window.
    private let viewport = CGRect(x: 0, y: 300, width: 400, height: 800)

    @Test("At full width the whole viewport is visible")
    func fullWidthIsUnchanged() {
        // The property that keeps every caller behaving exactly as it did
        // before zoom existed.
        #expect(ReaderZoom.visibleRegion(
            inViewport: viewport, scale: 1, pan: .zero
        ) == viewport)
    }

    @Test("Magnified, exactly 1/s of the viewport reaches the screen")
    func onlyABandIsVisible() {
        let band = ReaderZoom.visibleRegion(inViewport: viewport, scale: 3, pan: .zero)
        #expect(isClose(band.width, viewport.width / 3))
        #expect(isClose(band.height, viewport.height / 3))
    }

    @Test("With no pan the band sits in the middle of the viewport")
    func unpannedBandIsCentred() {
        let band = ReaderZoom.visibleRegion(inViewport: viewport, scale: 3, pan: .zero)
        #expect(isClose(band.midX, viewport.midX))
        #expect(isClose(band.midY, viewport.midY))
    }

    @Test("Panning to the limit puts the band against the edge it reveals")
    func panMovesTheBandToTheEdge() {
        // Asserted against the pan limit rather than a number, so this stays
        // true if the limit's definition ever changes.
        let limit = ReaderZoom.panLimit(containerLength: viewport.width, scale: 3)
        let left = ReaderZoom.visibleRegion(
            inViewport: viewport, scale: 3, pan: CGSize(width: limit, height: 0)
        )
        #expect(isClose(left.minX, viewport.minX))

        let right = ReaderZoom.visibleRegion(
            inViewport: viewport, scale: 3, pan: CGSize(width: -limit, height: 0)
        )
        #expect(isClose(right.maxX, viewport.maxX))
    }

    @Test("The vertical shift at a chapter's end moves the band with it")
    func endOfChapterShiftMovesTheBand() {
        let limit = ReaderZoom.panLimit(containerLength: viewport.height, scale: 3)
        let atTop = ReaderZoom.visibleRegion(
            inViewport: viewport, scale: 3, pan: CGSize(width: 0, height: limit)
        )
        #expect(isClose(atTop.minY, viewport.minY))
    }

    @Test("The band is expressed in the same coordinate space it was handed")
    func bandStaysInTheCallersSpace() {
        // The caller is a page whose own origin is not the viewport's, and the
        // cancel badge is placed by intersecting the two — so an answer in the
        // wrong space would put the badge somewhere plausible and wrong.
        let band = ReaderZoom.visibleRegion(inViewport: viewport, scale: 3, pan: .zero)
        #expect(viewport.contains(band))
    }
}

@Suite("Handing a pinch's vertical shift to the scroll view")
struct ReaderZoomScrollHandoffTests {

    @Test("The conversion reproduces the shift exactly, so nothing moves")
    func conversionIsExact() {
        // A point of scrolling moves the content `scale` points on screen, in
        // the opposite direction. Getting this wrong is visible as a jump at
        // the instant the fingers lift — the defect this model exists to remove.
        for scale in [CGFloat(1), 1.5, 3] {
            for pan in [CGFloat(-240), -30, 0, 30, 240] {
                let delta = ReaderZoom.scrollOffsetDelta(replacingVerticalPan: pan, scale: scale)
                #expect(isClose(-delta * scale, pan))
            }
        }
    }

    @Test("Shifting the content down means scrolling up, and the reverse")
    func directionIsInverted() {
        #expect(ReaderZoom.scrollOffsetDelta(replacingVerticalPan: 300, scale: 3) == -100)
        #expect(ReaderZoom.scrollOffsetDelta(replacingVerticalPan: -300, scale: 3) == 100)
    }

    @Test("A scale of zero cannot be divided by")
    func degenerateScaleIsSafe() {
        #expect(ReaderZoom.scrollOffsetDelta(replacingVerticalPan: 300, scale: 0) == 0)
    }
}
