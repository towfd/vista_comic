//
//  ReaderZoomTests.swift
//  vista_comicTests
//
//  Coverage for `reader-zoom` ticket 01.
//
//  Two things are under test here and they are not the same size. The scale
//  arithmetic is small and obvious. The arming gate is neither: it exists
//  because zooming changes the reader's content height by up to 3x, and the
//  bottom-edge inference that decides "the reader pulled past the end" reads
//  content height. Pinching from 3x back to 1x collapses the content to a
//  third of its height while the scroll offset is still the old, larger value,
//  which satisfies that inference anywhere past the first third of a chapter —
//  the same shape of false trigger `reader-auto-advance-false-trigger` was
//  opened for, except reproducible on demand.
//
//  So the cases below are organised around the transition, not around the
//  zoomed state: being zoomed is the easy half.
//

import Foundation
import SwiftUI
import Testing

@testable import vista_comic

@Suite("Reader zoom scale")
struct ReaderZoomScaleTests {

    @Test("A scale inside the bounds is left alone")
    func clampingPassesThroughInRange() {
        #expect(ReaderZoom.clamped(1.0) == 1.0)
        #expect(ReaderZoom.clamped(2.0) == 2.0)
        #expect(ReaderZoom.clamped(3.0) == 3.0)
    }

    @Test("Pinching in past full width settles at full width")
    func clampingStopsAtMinimum() {
        #expect(ReaderZoom.clamped(0.4) == ReaderZoom.minScale)
        #expect(ReaderZoom.minScale == 1.0)
    }

    @Test("Pinching out past the limit settles at the limit")
    func clampingStopsAtMaximum() {
        #expect(ReaderZoom.clamped(7.5) == ReaderZoom.maxScale)
        #expect(ReaderZoom.maxScale == 3.0)
    }

    @Test("Overshooting resists rather than stopping dead")
    func rubberBandingResistsBeyondTheBounds() {
        // Below the minimum: the reader still sees movement, but less of it,
        // so the bound is felt as a limit rather than as a stuck gesture.
        let under = ReaderZoom.rubberBanded(0.5)
        #expect(under < ReaderZoom.minScale)
        #expect(under > 0.5)

        let over = ReaderZoom.rubberBanded(4.0)
        #expect(over > ReaderZoom.maxScale)
        #expect(over < 4.0)
    }

    @Test("Inside the bounds there is nothing to resist")
    func rubberBandingPassesThroughInRange() {
        #expect(ReaderZoom.rubberBanded(1.0) == 1.0)
        #expect(ReaderZoom.rubberBanded(2.4) == 2.4)
        #expect(ReaderZoom.rubberBanded(3.0) == 3.0)
    }

    @Test("Rubber banding never produces a degenerate scale")
    func rubberBandingStaysPositive() {
        // A pinch can report a magnification approaching zero; a scale of zero
        // or below would collapse the strip's laid-out width.
        #expect(ReaderZoom.rubberBanded(0.001) > 0)
        #expect(ReaderZoom.rubberBanded(0) > 0)
    }

    @Test("At full width the strip is laid out exactly as it is today")
    func contentWidthAtMinimumIsTheContainer() {
        #expect(ReaderZoom.contentWidth(containerWidth: 393, scale: 1.0) == 393)
    }

    @Test("The strip's laid-out width is the container multiplied by the scale")
    func contentWidthScalesWithTheScale() {
        #expect(ReaderZoom.contentWidth(containerWidth: 393, scale: 2.0) == 786)
        #expect(ReaderZoom.contentWidth(containerWidth: 393, scale: 3.0) == 1179)
    }

    @Test("Before the first layout there is no width to scale")
    func contentWidthBeforeLayoutIsZero() {
        #expect(ReaderZoom.contentWidth(containerWidth: 0, scale: 3.0) == 0)
    }
}

@Suite("Reader bottom-edge arming gate")
struct ReaderBottomEdgeGateTests {

    /// A gate that has been armed the ordinary way: the reader is dragging the
    /// scroll view with one finger and has never zoomed.
    private func armedByScrolling() -> ReaderBottomEdgeGate {
        var gate = ReaderBottomEdgeGate()
        gate.scrollPhaseChanged(to: .tracking)
        return gate
    }

    // MARK: - Today's behaviour, which must survive unchanged

    @Test("A reader who has not touched the scroll view is not armed")
    func idleIsNotArmed() {
        #expect(ReaderBottomEdgeGate().isArmed == false)
    }

    @Test("Dragging arms the gate")
    func draggingArms() {
        #expect(armedByScrolling().isArmed)
    }

    @Test("Coasting after a fling still counts as driven")
    func deceleratingIsStillDriven() {
        var gate = ReaderBottomEdgeGate()
        gate.scrollPhaseChanged(to: .decelerating)
        #expect(gate.isArmed)
    }

    @Test("Coming to rest disarms the gate")
    func idlingDisarms() {
        var gate = armedByScrolling()
        gate.scrollPhaseChanged(to: .idle)
        #expect(gate.isArmed == false)
    }

    // MARK: - What zooming adds

    @Test("Starting a pinch disarms the gate immediately")
    func magnificationDisarms() {
        var gate = armedByScrolling()
        gate.magnificationBegan()
        #expect(gate.isArmed == false)
    }

    @Test("A scroll phase reported during a pinch does not re-arm the gate")
    func scrollDuringMagnificationDoesNotRearm() {
        // The scroll view can report tracking while two fingers are on it. If
        // that re-armed the gate, the interlock would be defeated by the very
        // gesture it exists to guard against.
        var gate = armedByScrolling()
        gate.magnificationBegan()
        gate.scrollPhaseChanged(to: .tracking)
        #expect(gate.isArmed == false)
    }

    @Test("While magnified the gate stays disarmed however the reader scrolls")
    func magnifiedScrollingIsNeverArmed() {
        var gate = ReaderBottomEdgeGate()
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 3.0)
        gate.scrollPhaseChanged(to: .tracking)
        #expect(gate.isArmed == false)
    }

    @Test("Returning to full width does not by itself re-arm the gate")
    func returningToFullWidthDoesNotRearm() {
        // This is the whole point. At the instant the scale crosses back to
        // 1.0 the content is still collapsing and the offset is still the old
        // one; re-arming here would fire the inference on that stale pair.
        var gate = armedByScrolling()
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)
        #expect(gate.isArmed == false)
    }

    @Test("A genuine one-finger scroll after the pinch re-arms the gate")
    func aRealScrollRearms() {
        var gate = ReaderBottomEdgeGate()
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)
        gate.scrollPhaseChanged(to: .tracking)
        #expect(gate.isArmed)
    }

    @Test("Momentum alone does not re-arm the gate")
    func decelerationDoesNotRearm() {
        // Re-arming is deliberately tied to a fresh touch rather than to any
        // sign of movement: a scroll view clamping its offset after the content
        // shrinks emits movement but no new touch.
        var gate = ReaderBottomEdgeGate()
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)
        gate.scrollPhaseChanged(to: .decelerating)
        #expect(gate.isArmed == false)
    }

    @Test("Changing chapter resets the gate")
    func chapterChangeResets() {
        var gate = armedByScrolling()
        gate.chapterChanged()
        #expect(gate.isArmed == false)
    }
}

@Suite("Zooming out never advances the chapter")
struct ReaderZoomCollapseRegressionTests {

    // A reader parked mid-chapter at 3x: thirty pages, each three times its
    // normal height because the strip is laid out three times as wide.
    private let containerHeight: CGFloat = 850
    private let magnifiedContentHeight: CGFloat = 30 * 1500 * 3
    private let magnifiedOffset: CGFloat = 15 * 1500 * 3
    // The same chapter one instant after the scale is committed back to 1.0.
    private let fullWidthContentHeight: CGFloat = 30 * 1500

    @Test("The collapse from 3x to full width clears the past-the-bottom test on geometry alone")
    func theCollapseLooksLikeAPull() {
        // The strip is laid out three times as wide at 3x, so every page — and
        // therefore the whole chapter — is three times as tall.
        #expect(magnifiedContentHeight == fullWidthContentHeight * 3)
        // Establishes that the hazard is real rather than theoretical: with the
        // gate armed, this geometry would advance the chapter.
        #expect(
            readerPassedBottom(
                contentOffsetY: magnifiedOffset,
                contentHeight: fullWidthContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: true,
                overscroll: 120
            )
        )
    }

    @Test("Pinching back to full width mid-chapter does not advance the chapter")
    func zoomingOutDoesNotAdvance() {
        var gate = ReaderBottomEdgeGate()
        gate.scrollPhaseChanged(to: .tracking)
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)

        #expect(
            readerPassedBottom(
                contentOffsetY: magnifiedOffset,
                contentHeight: fullWidthContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: gate.isArmed,
                overscroll: 120
            ) == false
        )
    }

    @Test("Pinching back to full width mid-chapter does not mark the chapter read")
    func zoomingOutDoesNotMarkRead() {
        var gate = ReaderBottomEdgeGate()
        gate.scrollPhaseChanged(to: .tracking)
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)

        #expect(
            readerPassedBottom(
                contentOffsetY: magnifiedOffset,
                contentHeight: fullWidthContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: gate.isArmed,
                overscroll: -1
            ) == false
        )
    }

    @Test("Pulling past the bottom still advances once the reader has scrolled again")
    func advancingStillWorksAfterZooming() {
        var gate = ReaderBottomEdgeGate()
        gate.magnificationBegan()
        gate.magnificationEnded(committedScale: 1.0)
        // The reader puts a finger down and scrolls for real.
        gate.scrollPhaseChanged(to: .tracking)

        let maxScroll = fullWidthContentHeight - containerHeight
        #expect(
            readerPassedBottom(
                contentOffsetY: maxScroll + 120,
                contentHeight: fullWidthContentHeight,
                containerHeight: containerHeight,
                isScrollDriven: gate.isArmed,
                overscroll: 120
            )
        )
    }
}
