//
//  SelectionCropMapping.swift
//  vista_comic
//
//  Pure coordinate math (no SwiftUI `View`, no OCR): converts an on-screen
//  text-selection rectangle drawn over a `.aspectRatio(contentMode: .fit)`
//  Page image (see `ReaderPage` in Features/ComicPage/ComicView.swift, for
//  context only — this file has no dependency on it) into the equivalent
//  crop rectangle in the Page's source-image pixel space, so a later ticket
//  can crop the original decoded image (not an on-screen screenshot) before
//  sending it to OCR. See .scratch/ocr-recognition/issues/02-selection-to-crop-mapping.md.
//

import CoreGraphics

/// Maps an on-screen selection rectangle to the equivalent crop rectangle in
/// a source image's pixel space, accounting for the scale and any
/// letterboxing/pillarboxing introduced by `.aspectRatio(contentMode: .fit)`.
///
/// Coordinate-space contract:
/// - `selection` and `displayFrameSize` share one coordinate space: origin at
///   the top-left, x increasing rightward, y increasing downward (SwiftUI's
///   default local coordinate space), in points.
/// - `displayFrameSize` is the size of the *container* the image is laid out
///   in with `.fit` — not necessarily the image's own rendered size. Because
///   `.fit` preserves aspect ratio, the actual image content can be
///   letterboxed (bars above/below) or pillarboxed (bars left/right) inside
///   that container when the container's aspect ratio doesn't match the
///   image's. Any part of `selection` that falls in those bars contributes
///   no pixels: it is clamped to the image's actual displayed bounds before
///   scaling.
/// - `imagePixelSize` is the source image's actual decoded pixel dimensions
///   (e.g. `CGImage.width`/`.height`, or `UIImage.size` scaled by
///   `UIImage.scale`).
enum SelectionCropMapping {
    /// Converts `selection` (drawn in `displayFrameSize`'s coordinate space)
    /// into the equivalent crop rectangle in `imagePixelSize`'s pixel space.
    ///
    /// - Returns: a pixel-space `CGRect`, clamped to
    ///   `(0, 0, imagePixelSize.width, imagePixelSize.height)`, directly
    ///   usable as the `rect` argument to `CGImage.cropping(to:)`. Returns
    ///   `.zero` when there is nothing to crop: `selection` doesn't overlap
    ///   the displayed image at all (entirely in a letterbox/pillarbox bar,
    ///   or — in the Reader's continuous scroll — off this Page and onto an
    ///   adjacent one), `selection` is degenerate (zero width or height), or
    ///   either input size is non-positive.
    static func cropRect(
        for selection: CGRect,
        displayFrameSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect {
        guard displayFrameSize.width > 0, displayFrameSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return .zero
        }

        // `.fit` scales uniformly by the smaller of the two axis ratios, so
        // the whole image fits without cropping; the other axis then has
        // leftover space split evenly as letterbox/pillarbox bars.
        let scale = min(
            displayFrameSize.width / imagePixelSize.width,
            displayFrameSize.height / imagePixelSize.height
        )
        let displayedImageSize = CGSize(
            width: imagePixelSize.width * scale,
            height: imagePixelSize.height * scale
        )
        let displayedImageOrigin = CGPoint(
            x: (displayFrameSize.width - displayedImageSize.width) / 2,
            y: (displayFrameSize.height - displayedImageSize.height) / 2
        )
        let displayedImageRect = CGRect(origin: displayedImageOrigin, size: displayedImageSize)

        // Normalize a possibly-negative-sized drag rect, then intersect with
        // the *displayed image's* bounds (not the container's) so any part
        // of the selection sitting in a letterbox/pillarbox bar, or entirely
        // outside the container, is dropped rather than mapped to pixels.
        // Computed manually (not via CGRect.intersection) so a zero-size
        // selection is treated as "no area" consistently, rather than
        // relying on CGRect's own empty-rect edge-case handling.
        let normalizedSelection = selection.standardized
        let minX = max(normalizedSelection.minX, displayedImageRect.minX)
        let minY = max(normalizedSelection.minY, displayedImageRect.minY)
        let maxX = min(normalizedSelection.maxX, displayedImageRect.maxX)
        let maxY = min(normalizedSelection.maxY, displayedImageRect.maxY)

        guard maxX > minX, maxY > minY else {
            return .zero
        }

        // Map the intersected, display-space rect back to source pixels:
        // subtract the displayed image's origin (undoes letterbox/pillarbox
        // offset), then divide by `scale` (undoes the `.fit` scale-down).
        let pixelRect = CGRect(
            x: (minX - displayedImageRect.minX) / scale,
            y: (minY - displayedImageRect.minY) / scale,
            width: (maxX - minX) / scale,
            height: (maxY - minY) / scale
        )

        // Defensive clamp against floating-point drift: the math above
        // should already keep `pixelRect` within the source image's bounds.
        let clampedMinX = min(max(pixelRect.minX, 0), imagePixelSize.width)
        let clampedMinY = min(max(pixelRect.minY, 0), imagePixelSize.height)
        let clampedMaxX = min(max(pixelRect.maxX, 0), imagePixelSize.width)
        let clampedMaxY = min(max(pixelRect.maxY, 0), imagePixelSize.height)

        return CGRect(
            x: clampedMinX,
            y: clampedMinY,
            width: clampedMaxX - clampedMinX,
            height: clampedMaxY - clampedMinY
        )
    }
}
