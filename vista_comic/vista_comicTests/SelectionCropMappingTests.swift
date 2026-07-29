//
//  SelectionCropMappingTests.swift
//  vista_comicTests
//
//  Table-driven coverage for `SelectionCropMapping.cropRect`, the pure
//  screen-selection → source-pixel-crop mapping used by the OCR selection
//  flow (see .scratch/ocr-recognition/issues/02-selection-to-crop-mapping.md).
//  No SwiftUI view or Vision involved — this is a coordinate-math unit.
//

import Testing
import Foundation
@testable import vista_comic

@Suite("SelectionCropMapping")
struct SelectionCropMappingTests {

    /// One row of the mapping table: a selection drawn in `displayFrameSize`'s
    /// coordinate space, mapped against an image of `imagePixelSize`, expected
    /// to produce `expected` in source-pixel space (within `tolerance` to
    /// absorb floating-point division).
    private struct Case {
        let name: String
        let selection: CGRect
        let displayFrameSize: CGSize
        let imagePixelSize: CGSize
        let expected: CGRect
        let tolerance: CGFloat

        init(
            _ name: String,
            selection: CGRect,
            displayFrameSize: CGSize,
            imagePixelSize: CGSize,
            expected: CGRect,
            tolerance: CGFloat = 0.001
        ) {
            self.name = name
            self.selection = selection
            self.displayFrameSize = displayFrameSize
            self.imagePixelSize = imagePixelSize
            self.expected = expected
            self.tolerance = tolerance
        }
    }

    private static let cases: [Case] = [
        // Container's aspect ratio exactly matches the image's, so `.fit`
        // introduces no letterboxing: display frame 300x400, image 600x800
        // (scale 0.5 both axes). A selection fully inside the display frame
        // should map by a uniform 1/0.5 = 2x factor.
        Case(
            "fully in-bounds selection, no letterboxing",
            selection: CGRect(x: 50, y: 100, width: 100, height: 150),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: CGSize(width: 600, height: 800),
            expected: CGRect(x: 100, y: 200, width: 200, height: 300)
        ),

        // Wide image (800x400, 2:1) fit into a square 400x400 container
        // letterboxes top/bottom: fitted image is 400x200, vertically
        // centered (y 100...300). A selection that overshoots both the left
        // edge (x < 0) and the top letterbox bar (y < 100) must be clamped
        // to the *displayed image's* bounds, not the container's, before
        // scaling back up by 1/0.5 = 2x.
        Case(
            "selection partially outside the image bounds, clamped to the letterboxed image",
            selection: CGRect(x: -50, y: 50, width: 200, height: 200),
            displayFrameSize: CGSize(width: 400, height: 400),
            imagePixelSize: CGSize(width: 800, height: 400),
            expected: CGRect(x: 0, y: 0, width: 300, height: 300)
        ),

        // A selection that is larger than the displayed image on every side
        // must clamp to exactly the full source image, not overflow it.
        Case(
            "selection fully enclosing the image clamps to the whole image",
            selection: CGRect(x: -50, y: -50, width: 400, height: 500),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: CGSize(width: 600, height: 800),
            expected: CGRect(x: 0, y: 0, width: 600, height: 800)
        ),

        // Selection drawn entirely to the right of the display frame, e.g.
        // a stray drag that never touched this Page at all — no overlap
        // with the image whatsoever.
        Case(
            "selection entirely outside the display frame does not intersect the image",
            selection: CGRect(x: 350, y: 50, width: 100, height: 100),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: CGSize(width: 600, height: 800),
            expected: .zero
        ),

        // Selection stays inside the *container* but lands entirely in the
        // top letterbox bar (y 0...100, above the fitted image's y 100...300)
        // — this stands in for "spans off the image entirely", the case a
        // continuous-scroll reader would hit if a drag strayed onto the
        // padding around an adjacent Page's frame.
        Case(
            "selection entirely inside a letterbox bar does not intersect the image",
            selection: CGRect(x: 10, y: 10, width: 50, height: 50),
            displayFrameSize: CGSize(width: 400, height: 400),
            imagePixelSize: CGSize(width: 800, height: 400),
            expected: .zero
        ),

        // A zero-size selection (e.g. a tap with no drag) has no area to
        // crop, regardless of where it sits.
        Case(
            "degenerate zero-size selection",
            selection: CGRect(x: 100, y: 100, width: 0, height: 0),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: CGSize(width: 600, height: 800),
            expected: .zero
        ),

        // A negative-size selection (a drag gesture reporting an
        // un-normalized rect, e.g. dragging up-and-left from the start
        // point) must be standardized before mapping, not treated as
        // degenerate or discarded.
        Case(
            "negative-size selection is standardized before mapping",
            selection: CGRect(x: 150, y: 250, width: -100, height: -150),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: CGSize(width: 600, height: 800),
            expected: CGRect(x: 100, y: 200, width: 200, height: 300)
        ),
    ]

    @Test("maps selection to expected source-pixel crop rect", arguments: cases)
    private func mapsSelectionToExpectedCropRect(_ testCase: Case) {
        let result = SelectionCropMapping.cropRect(
            for: testCase.selection,
            displayFrameSize: testCase.displayFrameSize,
            imagePixelSize: testCase.imagePixelSize
        )

        #expect(result.origin.x.isApproximatelyEqual(to: testCase.expected.origin.x, tolerance: testCase.tolerance))
        #expect(result.origin.y.isApproximatelyEqual(to: testCase.expected.origin.y, tolerance: testCase.tolerance))
        #expect(result.width.isApproximatelyEqual(to: testCase.expected.width, tolerance: testCase.tolerance))
        #expect(result.height.isApproximatelyEqual(to: testCase.expected.height, tolerance: testCase.tolerance))
    }

    // MARK: - Boundary / invalid-input cases (not part of the table above,
    // since they don't produce a meaningful "expected crop" beyond `.zero`)

    @Test("non-positive display frame size yields no crop")
    func nonPositiveDisplayFrameSizeYieldsNoCrop() {
        let result = SelectionCropMapping.cropRect(
            for: CGRect(x: 0, y: 0, width: 10, height: 10),
            displayFrameSize: .zero,
            imagePixelSize: CGSize(width: 600, height: 800)
        )
        #expect(result == .zero)
    }

    @Test("non-positive image pixel size yields no crop")
    func nonPositiveImagePixelSizeYieldsNoCrop() {
        let result = SelectionCropMapping.cropRect(
            for: CGRect(x: 0, y: 0, width: 10, height: 10),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: .zero
        )
        #expect(result == .zero)
    }

    @Test("result never exceeds the source image's pixel bounds")
    func resultNeverExceedsSourceImageBounds() {
        let imagePixelSize = CGSize(width: 600, height: 800)
        let result = SelectionCropMapping.cropRect(
            for: CGRect(x: -1000, y: -1000, width: 5000, height: 5000),
            displayFrameSize: CGSize(width: 300, height: 400),
            imagePixelSize: imagePixelSize
        )
        #expect(result.minX >= 0)
        #expect(result.minY >= 0)
        #expect(result.maxX <= imagePixelSize.width)
        #expect(result.maxY <= imagePixelSize.height)
    }
}

private extension CGFloat {
    func isApproximatelyEqual(to other: CGFloat, tolerance: CGFloat) -> Bool {
        abs(self - other) <= tolerance
    }
}
