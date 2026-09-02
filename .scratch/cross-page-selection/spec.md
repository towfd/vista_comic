Status: abandoned — built, then dropped by the repo owner before it was ever run (2026-09-02)

# Selection across page boundaries

> **This was not shipped, and the code that implemented it no longer exists.**
> All four tickets were written against this spec in one session and then
> reverted at the repo owner's request, unbuilt and unverified. What survives is
> this document, kept for the library measurements in it — they were expensive to
> establish and two of them overturned the obvious design. If the problem is
> picked up again, start from the decisions below rather than from scratch; treat
> the implementation notes as a plan that was never proven to compile.


## Problem Statement

The Reader's text selection cannot cross from one Page image to the next. A selection is drawn over a single `ReaderPage`, and `SelectionCropMapping.cropRect` intersects it with that Page's displayed bounds — anything past the seam is dropped, by design and with a test guarding it (`ocr-recognition` ticket 02).

That design assumed a piece of dialogue lives on one Page. In this library it frequently does not. The Pages are slices of a continuous webtoon strip, and the slicing is done by height with no regard for content, so the cut runs straight through speech bubbles and through the middle of individual letters. A reader who wants the line has no way to select it: they can take the top half or the bottom half, and neither half OCRs into anything, because a Vietnamese letter cut horizontally (`ê`, `ơ`, `ạ`) is not a letter in either piece.

## Solution

Let one selection span any number of consecutive Pages. The drag is owned by the Page it started on, as now; the part that overflows past that Page's top or bottom edge is mapped onto its neighbours, each contributing a band of its own source pixels. The bands are stitched vertically into a single image, in reading order, and that one image goes to OCR through the existing recognizer — reconstituting the pixels the slicing separated, so the recognizer sees what the original strip looked like before it was cut.

Nothing downstream of the crop changes: the stitched image enters `CroppedSelectionPreview` exactly as a single-page crop does today.

## Library facts this rests on

Measured against the developer's actual library rather than assumed, because two of them changed the design:

- **Every Page is 900px wide.** Verified across both comics. Uniform width plus `LazyVStack(spacing: 0)` means the strip is already pixel-continuous vertically, so stitching needs no width normalisation and no alignment decision.
- **900px is fewer pixels than the phone has.** Pages are laid out full-bleed at the container width (393pt at @3x = 1179 device px), so a Page is *upscaled* on screen, not downscaled.
- **Some chapters interleave 8px filler Pages.** `giao_duc_chan_chinh/03` alternates real Page / 8px Page from 062 to 100 — 20 of its 120 Pages. At the display scale (0.44) an 8px Page is ~3.5pt tall and effectively invisible. Any selection crossing a seam in that chapter therefore spans **three** images, not two.
- **The prefetch window is 5 Pages ahead, 2 behind** (`PagePrefetchWindow`), and both sides of a seam are on screen by definition, so a neighbour's decoded image is normally in hand.

## User Stories

1. As a reader, I want to select a line of dialogue that the page slicing cut in half, so that I can have it recognized as one piece of text instead of two unreadable halves.
2. As a reader, I want to see the whole selection rectangle while I draw it, including the part lying over the next Page, so that I know what I am selecting.
3. As a reader, I want a selection crossing an invisible filler Page to work like any other, so that a chapter whose slicing I cannot see does not behave differently for reasons I cannot perceive.
4. As a reader, I want to be told when a selection cannot be completed because one of the Pages it covers has not loaded, so that I do not receive a confidently wrong recognition of text with a piece missing.
5. As a reader, I want a kept line to point back at the Page where its text begins, so that jumping to the source puts the start of what I selected on screen.
6. As the developer, I want the multi-Page span arithmetic to be a pure, non-view unit, so that its correctness is verifiable by fast unit tests, the way the single-Page mapping already is.

## Implementation Decisions

Each was settled individually in a `/grilling` session; the reasoning is recorded because most of them had a plausible alternative.

- **Stitch pixels, not text.** The alternative — OCR each Page's band separately and join the strings — was rejected because the cut runs through individual letters, so each half recognizes as noise. Stitching restores the glyphs before the recognizer sees them.
- **Crop from the decoded source images, not from a screen capture.** A screen capture would solve cross-page for free, since the screen already composites the Pages, and the resolution objection is *weaker than the original spec assumed* (900px source vs 1179 device px means no loss at 1x). It was still rejected on three other grounds: the selection rectangle and controls are on screen and would be captured; a magnified capture is a re-upscaled raster, and magnification is exactly when the reader is chasing small text; and screen capture cannot be unit-tested, which moves all verification onto the device — the developer's own time.
- **Any number of consecutive Pages, not just two.** Forced by the 8px filler Pages: in `giao_duc_chan_chinh/03` every cross-seam selection spans three images. A two-Page limit would fail across that whole chapter for a reason the reader cannot see. The loop costs the same as the special case.
- **Filler Pages are cropped and stitched like any other, never skipped.** Their 8 rows are real pixels the slicing removed; dropping them would shorten the stitched image by 8 rows that may hold part of a glyph.
- **The gesture and the arithmetic stay on the starting Page, using relative overflow.** The alternative — a Reader-level overlay using absolute strip coordinates — was rejected because absolute positions are a cumulative sum over every Page's height, and Pages never decoded contribute an estimate (`reservedPageHeight`'s chapter median). One wrong estimate offsets everything. Relative overflow only needs the neighbours' heights, and neighbours are on screen and therefore decoded.
- **Raise the drawing Page's `zIndex` while a drag is in flight.** Sibling rows in a `LazyVStack` draw in order, so a rectangle extending downward is currently occluded by the next Page — precisely where this feature needs to be visible. **Unverified**: `zIndex` behaviour inside `LazyVStack` must be confirmed on a device. If it does not hold, the fallback is to hoist only the *drawing* to Reader level while the arithmetic stays on the starting Page — not to adopt absolute coordinates.
- **A Page in the span whose image is not in hand fails the whole selection**, with a message naming the unloaded Page. Silently omitting a band would produce a plausible-looking recognition of text with a hole in it, which is worse than a failure because the reader cannot detect it. Waiting for a load would put an unbounded await on the gesture-end path. A failed Page is already visible as a failure placeholder and already has a retry, so the message is actionable. *Known wrinkle*: this blocks a selection when the missing Page is an 8px filler contributing nothing visible; avoiding that would need a magic minimum-contribution threshold, deliberately not introduced.
- **`CroppedSelection.pageNumber` records the topmost Page in the span.** The starting Page was rejected as direction-dependent — dragging up and dragging down over the same rectangle would record different Pages, decided by something the reader cannot see. Largest-contributing-area has the same instability near a tie. The topmost Page is direction-independent, puts `SourceReference.peekRoute` at the point where the text begins, and is the Page whose image the comprehension worker will read.
- **`SelectionCropMapping` is untouched; the span logic layers above it.** Every band is still one rectangle against one image with one `.fit` scale, which is what that function already does correctly and has tests for. The new unit decides *which* Pages and *how much of each*, and hands each band to the existing function.
- **The selection stays bounded by the viewport.** Edge auto-scroll is not added; see Out of Scope.

## Testing Decisions

- **Span arithmetic is a pure unit with table-driven tests**, mirroring `SelectionCropMappingTests`: given a starting Page, a drag rectangle and the neighbours' displayed heights, assert the list of (Page index, crop rectangle) bands. Boundary cases: no overflow at all (one band, identical to today's behaviour); overflow upward; overflow downward; overflow past a whole Page into the one beyond it; a span containing an 8px Page; overflow past the first and last Pages of the chapter, which must clamp rather than address a Page that does not exist.
- **Stitching is a separate pure unit**: given bands of known sizes, assert the output dimensions and the order. Pixel-exactness of the seam is not asserted — that is what the device check is for.
- **The unloaded-Page refusal is asserted at the flow level**, not by rendering: given a span where one Page has no decoded image, no crop is produced and the failure is reported.
- **No XCUITests.** UI verification belongs to the repo owner; the deliverable for UI-facing behaviour is the device-check list below.

### Device checks for the repo owner

1. Drawing a rectangle downward across a seam shows the whole rectangle, including the part over the next Page — the `zIndex` question above.
2. A selection across a seam recognizes as one continuous line rather than two fragments.
3. The same in `giao_duc_chan_chinh/03` past Page 62, where the span silently includes an 8px Page.
4. Dragging upward across a seam behaves identically to dragging downward, and the kept line points at the upper Page.
5. A selection covering a Page that failed to load reports the failure instead of returning partial text.
6. Normal single-Page selection is unchanged, and the cancel badge still works mid-drag.

## Out of Scope

- **Edge auto-scroll while selecting.** Selection deliberately disables scrolling so the `ScrollView` does not contest the drag for the touch; re-enabling it means reopening that gesture conflict, plus scroll speed, acceleration, and what to do when the Pages scrolled into view have not decoded — which the refusal rule above would immediately trigger. A reader who needs a taller selection can zoom out first, which is an operation they already know. This is a larger feature than the one specified here, not a detail of it.
- **Carrying a Page *range* on a kept record.** A cross-page selection's explanation shows the comprehension worker only one Page of visual context (`comprehension_worker.run_record` reads one Page by `page_number`). Fixing that properly means a schema and API change, deliberately not folded in here.
- **Automatic bubble detection.** Still manual rectangle selection, as in `ocr-recognition`.
- **Horizontal spanning.** Pages are uniform width and full-bleed; there is no adjacent Page sideways.
- **Any backend change.** This is a pure iOS-side increment.

## Further Notes

- **This reverses a decision `ocr-recognition` took deliberately.** That spec lists "selection spanning into an adjacent Page" as a boundary case returning `.zero`, with a test asserting it. That spec is not being edited — it is the record of what was decided and shipped at the time — but `SelectionCropMapping`'s doc comment should be updated to point at the new layer, and the test asserting the old behaviour changes meaning: a page-local crop still clamps, and it is now the span layer's job to have already split the rectangle.
- The design was converged through `/grilling` on 2026-09-02. Seven decisions were put individually and each was confirmed; two of them (Pages-per-span, and screen capture versus source crop) turned on library measurements taken during the session rather than on preference.
