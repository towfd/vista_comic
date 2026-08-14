//
//  ReaderZoom.swift
//  vista_comic
//
//  The reader-zoom feature's logic, kept out of `ComicView.swift` for the same
//  reason `readerPassedBottom` and `readerStartIndex` are free functions there:
//  so it can be exercised without rendering the reader. See
//  `.scratch/reader-zoom/spec.md`.
//
//  Zoom is a change of *layout width*, not a rendering transform. The pages
//  stack is laid out at the container width multiplied by the scale, so the
//  pages genuinely become wider and — being fitted at a fixed aspect ratio —
//  proportionally taller. Everything the reader already derives from its scroll
//  view therefore keeps working natively, including the reserved-height
//  calculation, which was already parameterised by width.
//
//  That is also the source of this file's second, larger half. Content height
//  is one of the three numbers `readerPassedBottom` reads, and zoom moves it by
//  up to 3x.
//

import SwiftUI

// MARK: - Scale

/// The bounds and arithmetic of the reader's magnification.
enum ReaderZoom {
    /// Full width — today's reader exactly, and the bottom of the gesture, so
    /// "back to normal" needs no control to find.
    static let minScale: CGFloat = 1.0

    /// Chosen as a legibility judgement rather than a technical limit. Every
    /// Page in this library is 900px wide, and a large phone already renders
    /// that across ~1290 device pixels, so full width is a 1.43x upscale before
    /// any zoom at all. At 3x the source is stretched 4.3x: text is large, and
    /// pixel edges are visible. Past this it stops being magnification of
    /// anything legible.
    static let maxScale: CGFloat = 3.0

    /// How much of an overshoot past a bound is still expressed on screen.
    /// Movement continues, but visibly damped, so the reader feels a limit
    /// rather than a stuck gesture.
    private static let overshootResistance: CGFloat = 0.35

    /// Where a gesture settles once the fingers lift.
    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    /// What to show *during* a gesture that has gone past a bound.
    ///
    /// Floored well above zero: a pinch can report a magnification approaching
    /// zero, and a scale of zero or below would collapse the strip's laid-out
    /// width rather than merely making it small.
    static func rubberBanded(_ scale: CGFloat) -> CGFloat {
        if scale < minScale {
            let resisted = minScale - (minScale - scale) * overshootResistance
            return max(resisted, minScale * (1 - overshootResistance))
        }
        if scale > maxScale {
            return maxScale + (scale - maxScale) * overshootResistance
        }
        return scale
    }

    /// The width the pages stack is laid out at.
    ///
    /// Zero before the first layout has established a container width, which
    /// the reader reads as "no width to impose yet" and lets the stack size
    /// itself as it does today.
    static func contentWidth(containerWidth: CGFloat, scale: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return 0 }
        return containerWidth * clamped(scale)
    }
}

// MARK: - Live scroll metrics

/// Where the pages scroll view currently sits, how big its content is, and how
/// big the window onto it is.
///
/// Read only when a pinch begins or commits, and when the container resizes —
/// never during layout — so that a zoom can be anchored at, and re-anchored to,
/// the content the reader is actually looking at.
struct ReaderScrollMetrics: Equatable {
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var containerSize: CGSize = .zero

    /// The content under `focal` — a unit point within the *viewport* — as a
    /// unit point within the whole strip.
    ///
    /// This is the translation the pinch needs: a gesture reports where the
    /// fingers are on screen, while the transform that follows them has to be
    /// anchored in the content's own coordinate space, which is up to three
    /// screens wide and many screens tall.
    func contentAnchor(forFocal focal: UnitPoint) -> UnitPoint {
        guard contentSize.width > 0, contentSize.height > 0 else { return .center }
        let point = viewportPointInContent(focal)
        return UnitPoint(
            x: Self.clampedToUnit(point.x / contentSize.width),
            y: Self.clampedToUnit(point.y / contentSize.height)
        )
    }

    /// Where the scroll offset has to move once the strip has been re-laid-out
    /// `ratio` times larger, so that the content under `focal` is still under
    /// `focal`.
    ///
    /// Without this the reader is thrown through the chapter by exactly the
    /// proportion the content grew — zooming to 3x would leave them a third of
    /// the way back from where they were reading.
    func offset(afterScalingBy ratio: CGFloat, focal: UnitPoint) -> CGPoint {
        let anchorInViewport = CGPoint(
            x: focal.x * containerSize.width,
            y: focal.y * containerSize.height
        )
        let point = viewportPointInContent(focal)
        return CGPoint(
            x: max(0, point.x * ratio - anchorInViewport.x),
            y: max(0, point.y * ratio - anchorInViewport.y)
        )
    }

    /// The content coordinate currently displayed at `focal`.
    private func viewportPointInContent(_ focal: UnitPoint) -> CGPoint {
        CGPoint(
            x: offset.x + focal.x * containerSize.width,
            y: offset.y + focal.y * containerSize.height
        )
    }

    private static func clampedToUnit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// A box holding the metrics above.
///
/// Exists so they can be updated on every frame of every scroll without
/// invalidating the reader's body, which storing them in `@State` would do.
/// Only ever touched from the main actor — the conformance is what lets it live
/// in a `@State` property, not a claim that it is safe to share.
final class ReaderScrollMetricsBox: @unchecked Sendable {
    var value = ReaderScrollMetrics()
}

// MARK: - The bottom-edge arming gate

/// Decides whether the reader's bottom-edge inferences can be trusted right now.
///
/// `readerPassedBottom` decides "the reader pulled past the end" from content
/// offset, content height and container height. Those three numbers describe
/// where the content sits, not how it got there — which is why that function
/// already refuses to answer unless the scroll view was being driven by the
/// reader. Zoom adds a second way for the same numbers to lie, and a worse one.
///
/// **The dangerous direction is downward.** Pinching from 3x back to full width
/// collapses the content to a third of its height while the scroll offset is
/// still the old, larger value. That pair satisfies the past-the-bottom test
/// anywhere beyond the first third of a chapter, and the further in the reader
/// was, the more certainly it does. Left alone it would advance the chapter, or
/// mark it read, every time the reader zoomed out — the same failure PR #65
/// fixed for a keyboard-driven collapse, except reproducible on demand.
///
/// So the gate closes on the *gesture* and reopens only on another gesture:
/// a pinch disarms it, and only a genuine one-finger drag re-arms it. This is
/// deliberately not a timer and not a delay. A scroll view clamping its offset
/// after its content shrinks emits geometry updates but produces no new touch,
/// so requiring a touch closes the window structurally rather than racing it.
struct ReaderBottomEdgeGate: Equatable {
    /// Whether the scroll view is under the reader's finger or coasting from
    /// it — the original gate, unchanged in meaning.
    private var isScrollDriven = false

    /// Whether a pinch is in progress right now.
    private var isMagnifying = false

    /// The scale the layout is currently committed to. While this is not full
    /// width the inferences stay shut regardless of everything else.
    private var committedScale: CGFloat = ReaderZoom.minScale

    /// Set by a pinch and cleared only by a real drag. This is the part that
    /// covers the transition back to full width, where `committedScale` has
    /// already returned to 1.0 but the content has not finished collapsing.
    private var awaitsRearmingScroll = false

    var isArmed: Bool {
        isScrollDriven
            && !isMagnifying
            && committedScale == ReaderZoom.minScale
            && !awaitsRearmingScroll
    }

    mutating func magnificationBegan() {
        isMagnifying = true
        awaitsRearmingScroll = true
    }

    mutating func magnificationEnded(committedScale: CGFloat) {
        isMagnifying = false
        self.committedScale = committedScale
    }

    mutating func scrollPhaseChanged(to phase: ScrollPhase) {
        // Deceleration counts as driven: releasing a fling that coasts to the
        // bottom is a normal way to finish a chapter, and the geometry update
        // that crosses the threshold usually arrives after the finger has left.
        isScrollDriven = phase == .tracking
            || phase == .interacting
            || phase == .decelerating

        // Re-arming is narrower than being driven, and only tracking — a finger
        // actually down and moving — counts. Momentum does not, because that is
        // what an offset clamp looks like from here.
        if phase == .tracking, !isMagnifying {
            awaitsRearmingScroll = false
        }
    }

    /// The scroll view is rebuilt for a new chapter and the scale returns to
    /// full width, so nothing learned about the old one carries over.
    mutating func chapterChanged() {
        self = ReaderBottomEdgeGate()
    }
}
