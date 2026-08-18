//
//  ReaderZoom.swift
//  vista_comic
//
//  The reader-zoom feature's logic, kept out of `ComicView.swift` for the same
//  reason `readerPassedBottom` and `readerStartIndex` are free functions there:
//  so it can be exercised without rendering the reader. See
//  `.scratch/reader-zoom/spec.md`.
//
//  Zoom is an *absolute transform over the viewport*, and the layout never
//  changes. The pages stack stays laid out at the container width at every
//  magnification; the scale — an absolute value over 1...3, never a ratio
//  against anything — lives only in the rendering layer. The scroll view is
//  therefore never told that zoom exists: content offset, content size and
//  container size hold the same values at 3x as at 1.0.
//
//  That invariance is what this file is short for. Nothing is committed when
//  the fingers lift, so there is no offset to re-anchor and nothing that can be
//  clamped against a content size that has not grown yet; and because content
//  height cannot move with the scale, the bottom-edge inferences need no gate
//  of their own beyond the scroll-driven one they already had.
//
//  The previous model laid the strip out at `containerWidth × scale` and
//  committed that width on release. It was built, device-tested and rejected —
//  see `.scratch/reader-zoom/issues/01-pinch-to-zoom-the-strip.md` for the
//  measurements.
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

    /// How much of an overshoot past the *upper* bound is still expressed on
    /// screen. Movement continues, but visibly damped, so the reader feels a
    /// limit rather than a stuck gesture.
    private static let overshootResistance: CGFloat = 0.35

    /// Anything below this settles at full width rather than just above it.
    ///
    /// Still load-bearing under this model, for one reason: auto-advance is
    /// deliberately inert whenever the scale is not exactly full width, so a
    /// reader who pinches back to "normal" and stops at 1.03 would silently
    /// lose the ability to reach the next chapter, with nothing on screen to
    /// explain why.
    static let snapToFullWidthBelow: CGFloat = 1.08

    /// Where a gesture settles once the fingers lift.
    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    /// What the scale becomes when the fingers lift: clamped, then snapped to
    /// full width if it is close enough that the reader meant full width.
    ///
    /// Note what this is *not*: nothing is laid out again as a result. The
    /// value the gesture settles on is simply the value the transform keeps,
    /// which is why there is no moment at which the reader can be displaced.
    static func settled(_ scale: CGFloat) -> CGFloat {
        let clamped = clamped(scale)
        return clamped < snapToFullWidthBelow ? minScale : clamped
    }

    /// What to render *during* a gesture that has gone past a bound.
    ///
    /// Asymmetric on purpose. Past the upper bound the overshoot is damped and
    /// still shown, so the reader feels the ceiling. Below full width it is
    /// damped and then **floored at full width**: a viewport drawn smaller than
    /// the screen is not a state this reader has. The previous model could not
    /// express that — its transform was a ratio against a committed layout, so
    /// it went below 1 for the whole duration of every zoom-out gesture and
    /// visibly shrank the reader away from the screen edges.
    static func rubberBanded(_ scale: CGFloat) -> CGFloat {
        if scale < minScale { return minScale }
        if scale > maxScale {
            return maxScale + (scale - maxScale) * overshootResistance
        }
        return scale
    }
}

// MARK: - Panning

extension ReaderZoom {
    /// How far the magnified content can be moved along one axis, in screen
    /// points, in either direction from centred.
    ///
    /// At scale `s` only `1/s` of the viewport is on screen, and the part that
    /// is not reaches `containerLength × (s − 1) / 2` past each edge. Zero at
    /// full width, which is what makes every pan expression below inert at 1.0
    /// without needing to special-case it.
    static func panLimit(containerLength: CGFloat, scale: CGFloat) -> CGFloat {
        guard containerLength > 0 else { return 0 }
        return max(0, containerLength * (clamped(scale) - 1) / 2)
    }

    /// A pan held inside what the magnified content can actually show, so that
    /// dragging sideways stops at the edge of the page rather than pulling
    /// background into view.
    static func clampedPan(_ pan: CGFloat, containerLength: CGFloat, scale: CGFloat) -> CGFloat {
        let limit = panLimit(containerLength: containerLength, scale: scale)
        return min(max(pan, -limit), limit)
    }

    /// The pan along one axis that keeps whatever is currently under `focal`
    /// under `focal` once the scale changes from `oldScale` to `newScale`.
    ///
    /// Pure arithmetic on the container size, which is the point: it reads
    /// nothing about content size, so unlike the offset correction the previous
    /// model needed, there is no stale measurement for it to be wrong about.
    ///
    /// - Parameter focal: where the fingers are, as a fraction of the container.
    static func panKeepingFocalPoint(
        focal: CGFloat,
        containerLength: CGFloat,
        previousPan: CGFloat,
        from oldScale: CGFloat,
        to newScale: CGFloat
    ) -> CGFloat {
        guard containerLength > 0, oldScale > 0 else { return previousPan }
        let middle = containerLength / 2
        let focalPoint = focal * containerLength
        // Where the focal point lands in the untransformed viewport.
        let source = middle + (focalPoint - middle - previousPan) / oldScale
        return focalPoint - middle - newScale * (source - middle)
    }
}

// MARK: - Reaching the ends of a chapter

extension ReaderZoom {
    /// How much further than strictly necessary the end-of-chapter shift takes
    /// to decay as the reader scrolls away from an end.
    ///
    /// At `1` the shift is spent over exactly the distance that needed it,
    /// which means the content travels at twice the normal rate for that
    /// stretch. Spreading it wider trades a longer stretch for a gentler one:
    /// the excess is `1 + 1/factor`, so 2.5 puts it at 1.4x, which reads as the
    /// chapter's first screen settling rather than as the reader being pushed.
    static let endReachSettling: CGFloat = 2.5

    /// The vertical shift that makes a chapter's first and last screen readable
    /// while magnified.
    ///
    /// Vertical movement belongs to the scroll view — with one exception. At
    /// either end of a chapter, scrolling runs out before the magnified band
    /// has covered the content there: at 3x on an 800pt viewport the outermost
    /// ~267pt of the first and last screen can never be scrolled into the band,
    /// because there is no scrolling left to do it with. This supplies exactly
    /// that shift, and decays to zero as soon as scrolling can take over.
    ///
    /// Derived from the scroll position rather than driven by a finger, which
    /// is the one deliberate deviation from Mihon's and Kotatsu's clamped
    /// translation. Their version requires the reader to hold a drag to see the
    /// end of a chapter; this one just shows it, and it removes the gesture
    /// arbitration that would otherwise have to decide, mid-drag, whether a
    /// vertical movement belongs to the scroll view or to the transform.
    ///
    /// Positive moves content down the screen (revealing what is above it).
    static func endOfChapterPan(
        scrollOffset: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let reach = panLimit(containerLength: containerHeight, scale: scale)
        guard reach > 0 else { return 0 }
        let maxOffset = max(0, contentHeight - containerHeight)
        let offset = min(max(scrollOffset, 0), maxOffset)
        // A point of scrolling moves the content `scale` points on screen, so
        // that is the rate at which the shift stops being needed — divided by
        // the settling factor, which is what spreads it over a longer stretch
        // of scrolling and so makes the excess speed smaller.
        let decay = clamped(scale) / endReachSettling
        let fromTop = max(0, reach - offset * decay)
        let fromBottom = max(0, reach - (maxOffset - offset) * decay)
        return fromTop - fromBottom
    }

    /// The part of the viewport the reader can actually see, in the same
    /// coordinate space as `viewport`.
    ///
    /// Nothing in the view hierarchy reports this. The scroll view is
    /// unmagnified at every scale, so `bounds(of: .scrollView)` describes the
    /// whole viewport whatever the magnification — and at scale `s` only `1/s`
    /// of it reaches the screen, with the pan deciding which `1/s`. Anything
    /// that has to stay reachable, the selection cancel badge above all, has to
    /// be placed against this rather than against the scroll view's bounds.
    ///
    /// Returns the viewport unchanged at full width, which is what makes every
    /// caller behave exactly as it did before zoom existed.
    static func visibleRegion(inViewport viewport: CGRect, scale: CGFloat, pan: CGSize) -> CGRect {
        let scale = clamped(scale)
        guard scale > minScale else { return viewport }
        let width = viewport.width / scale
        let height = viewport.height / scale
        return CGRect(
            x: viewport.minX + (viewport.width - width) / 2 - pan.width / scale,
            y: viewport.minY + (viewport.height - height) / 2 - pan.height / scale,
            width: width,
            height: height
        )
    }

    /// The scroll-offset change that reproduces `pan` exactly, so a transient
    /// vertical pan can be handed to the scroll view when a pinch ends without
    /// anything moving on screen.
    ///
    /// A point of scrolling moves the content `scale` points on screen, and in
    /// the opposite direction, which is the whole conversion. It is exact — and
    /// safe in a way the previous model's commit was not — because content size
    /// does not change with the scale, so there is no stale size for the
    /// resulting offset to be clamped against.
    static func scrollOffsetDelta(replacingVerticalPan pan: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return 0 }
        return -pan / scale
    }
}

// MARK: - Live scroll metrics

/// Where the pages scroll view currently sits, how big its content is, and how
/// big the window onto it is.
///
/// Read when a pinch ends and while deciding how far the end-of-chapter shift
/// still applies — never to correct for a layout change, because there is no
/// longer a layout change to correct for.
struct ReaderScrollMetrics: Equatable {
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var containerSize: CGSize = .zero
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
