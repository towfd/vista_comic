# 01 — Pinch to zoom the strip, without breaking auto-advance

**What to build:** A reader who finds a title's lettering too small pinches, and the whole vertical strip enlarges. The magnification is a property of reading, not of a Page: it persists as they scroll from Page to Page, so it is set once rather than re-established on every Page. Pinching back in returns to the normal full-width view, and the scale stops there — full width is the bottom of the gesture, so "back to normal" needs no control to find. The upper bound is 3x. Both bounds rubber-band rather than stopping dead, so the reader feels a limit instead of a stuck gesture.

At 1.0 the Reader must be indistinguishable from today's.

Zoom is an **absolute transform over the viewport**, and the layout never changes. The pages stack stays laid out at `containerWidth` at every magnification, and the scale — an absolute value over `1.0...3.0`, never a ratio against anything — lives only in the rendering layer. The scroll view is therefore never told that zoom exists: `contentOffset`, `contentSize` and `containerSize` hold the same values at 3x as at 1.0, and the reader's position is always a coordinate in the unmagnified strip. Nothing is committed when the fingers lift, so there is no moment at which the reader can be displaced.

**What has to be built is the panning.** The strip never becomes genuinely wider, so the scroll view has no horizontal axis to give away, and at scale `s` only `1/s` of the viewport is on screen. Horizontal movement is a transform offset this ticket owns and clamps. Vertical movement stays with the scroll view — except at the two ends of a chapter, where scrolling runs out before the magnified band has covered the first and last screen of content, and the same clamped offset takes over. Mihon's `zoomScrollBy` and Kotatsu's clamped `translationX`/`translationY` are this same mechanism; neither gets panning for free either.

**The pinch's focal point is split across two mechanisms, and they have to agree.** The horizontal component is applied to the pan. The vertical component is applied as a change to the scroll offset, so that the reader has one vertical mechanism rather than two competing ones. That offset change is safe in a way the old commit was not: content size never changes, so it cannot be clamped against a stale one.

**The bottom-edge inferences stop needing defending.** `readerPassedBottom` reads content offset, content height and container height, and zoom can no longer affect any of the three. The arm/disarm state machine in `ReaderBottomEdgeGate` is therefore deleted, and what remains is the pre-existing PR #65 discipline — the inference is trusted only while the scroll view is being driven by the reader — which is for the keyboard-collapse case, is unrelated to zoom, and stays as it is. The two consumers then split:

- **Read detection is restored at every scale.** A chapter read to its end while magnified is marked `read`. The previous ticket's accepted consequence (that it stayed `reading`) was a symptom of the old model, not a decision.
- **Auto-advance stays inert while the scale is not 1.0** — a product rule, kept deliberately, so that examining a magnified panel can never turn into a chapter change. One scale check, not a state machine.

The scale and the pan offset both return to their defaults whenever the chapter changes and whenever the Reader is dismissed. Nothing is persisted anywhere — no per-comic memory, no user defaults, no store.

**Blocked by:** None.

**Status:** done — device-verified by the repo owner, 2026-08-18 (branch `feat/reader-zoom`)

**Device-verified, 2026-08-18.** All three of the checks that decided this rewrite pass: nothing moves at the instant the fingers lift, deep inside a long chapter; pinching out from 3x never draws the reader smaller than the screen; and at 3x the first and last screen of a chapter are fully visible without holding a drag. The 1.4x settle at the chapter ends was accepted as-is, so `ReaderZoom.endReachSettling` stays at 2.5.

Builds on iPhone 16 Pro Max and iPhone SE (3rd generation); 237 unit tests pass, none failing — the three failures in the run are all XCUITests, which this environment's accessibility runner cannot initialise and which this repo does not have Claude write or run.

**One deviation from the spec as written, made during implementation.** The end-of-chapter vertical shift is **derived from the scroll position rather than driven by a finger**. The spec described it as a pan taking over where scrolling runs out, which is what Mihon and Kotatsu do — and what they do requires the reader to hold a drag in order to see the end of a chapter. Deriving it shows them instead, and removes the gesture arbitration that would otherwise have to decide, mid-drag, whether a vertical movement belongs to the scroll view or to the transform. That arbitration was this ticket's stated top risk. The cost is that the shift has to decay as scrolling takes over, so content moves 1.4x the finger over that stretch (`ReaderZoom.endReachSettling`); the number is a guess and the device pass is what should decide it.

## Acceptance criteria

- [x] Pinching enlarges the whole strip, and the magnification persists while scrolling from Page to Page
- [x] The scale is bounded to 1.0–3.0, and both bounds rubber-band and settle at the bound
- [x] The rendered viewport is **never** drawn smaller than the screen, at any point in any gesture, including mid-rubber-band below 1.0
- [x] Nothing moves at the instant the fingers lift — there is no commit, and no re-layout, at any scale
- [x] At 1.0 the Reader renders and behaves identically to before this ticket
- [x] Zooming is centred on the pinch's focal point, with the horizontal component applied to the pan and the vertical component applied to the scroll offset
- [x] While magnified, dragging sideways reveals the rest of the Page, clamped to the magnified content
- [x] While magnified, the first and last screen of a chapter are fully reachable, the shift is zero everywhere else in the chapter, and it decays smoothly rather than snapping away
- [x] The horizontal pan offset is preserved while scrolling vertically
- [x] Changing chapter returns the scale and the pan offset to their defaults; leaving the Reader does the same; nothing is persisted
- [x] The pages stack's laid-out width is `containerWidth` at every scale, and `contentSize` is unchanged by zoom — asserted directly, since this is the property everything else in this ticket rests on
- [x] Auto-advance does not fire while the scale is not 1.0
- [x] Read detection works at every scale, including a chapter read to its end entirely while magnified
- [x] `ReaderBottomEdgeGate`'s arm/disarm state machine is removed, and the pre-existing PR #65 scroll-driven gate is left untouched, with its existing tests passing unchanged
- [x] The rotation offset correction is removed, and rotating or resizing while magnified keeps the reader where they were
- [x] Per-Page progress reporting, prefetching, retention and preview (peek) mode are unaffected at every scale
- [x] Tapping to show and hide the controls remains immediate, with no double-tap disambiguation delay introduced
- [x] Unit tests cover clamping at both bounds, the floor that keeps the rendered scale at or above 1.0, pan clamping horizontally and vertically (including that mid-chapter yields no vertical slack), the focal-point vertical conversion, and that read detection and auto-advance are armed differently
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout

## Verify on device — the handoff, per `CLAUDE.md`'s verification rules

In rough order of what would hurt most if wrong:

- Read a chapter normally without zooming at all, on both a compact and a large phone: page size, scrolling, tapping to show and hide the controls, and pulling past the bottom to advance must all feel exactly as before.
- **Pinch and let go, deep inside a long chapter.** Nothing should move at the moment the fingers lift. This is the defect this rewrite exists for; the old model displaced the reader further the deeper into the chapter they were.
- **Pinch out from 3x back to full width.** The reader must never be drawn smaller than the screen at any point in the gesture — no background showing around a shrunken page.
- Pinch slowly and check what was under the fingers is still under them, both zooming in and zooming out.
- Zoom to 3x and pan to the left and right edges of a page; confirm it stops at the edge rather than drifting past it.
- **At 3x, scroll to the very top and the very bottom of a chapter.** The first and last screen of content must be fully visible without holding a drag. Then scroll away from that end and watch the settle: content moves ~1.4x the finger for roughly the first two-thirds of a screen. If that reads as being pushed rather than as settling, `ReaderZoom.endReachSettling` is the number to raise.
- Zoom in, then scroll several pages: the magnification stays, the horizontal position stays, and pages keep loading at the right size.
- Read a chapter to its end entirely while magnified: it must be marked read. Then confirm it did **not** advance to the next chapter.
- Rotate the device while at 3x, and on iPad resize the window: the strip should stay coherent and you should stay roughly where you were.
- Change chapter while magnified, and leave and re-enter the reader: both must come back at full width with the pan reset.
- Resume: reopen a chapter you were part-way through, jump to a page from 歷史紀錄, and auto-advance past the end of a chapter.
- **Scroll downward faster than pages can load, at 1.0 and again at 3x.** This is the one condition prefetching does not cover, and it is the trigger for reopening `.scratch/page-dimensions/`. If content shoves here, say so.
- Selection still works at full width — magnified selection is ticket 02.

## Comments

### The layout-width model: built, device-tested, rejected

This ticket originally specified zoom as a **change of layout width** — the strip laid out at `containerWidth × scale` inside a two-axis scroll view, with the new width committed when the fingers lifted. It was implemented in full and partly device-verified before being rejected. The reasoning is kept because two of the decisions that looked correct at the time were the ones that failed.

**Device-verified by the repo owner, 2026-08-16:** the bottom-edge interlock worked in both directions — reaching the bottom while magnified did not change chapter, and returning to full width restored auto-advance. It was reported broken on the first device pass and took two independent fixes (snapping the committed scale to exactly 1.0, and re-arming on either touch phase rather than `tracking` alone). They shipped together, so which one was the actual cause is no longer determinable.

**What the second device pass found, 2026-08-18.** The reader was displaced **at the instant the fingers lifted**, and only then. Scrolling through pages that had not been loaded yet caused no observable displacement, at 1.0 or at 3x. Two conclusions follow:

1. **The commit is the defect, and it is not fixable in that model.** Committing a new width changes content size, so the scroll offset must be re-anchored — but the assignment is evaluated against the pre-growth content size, and `scrollTo(point:)` is documented to clamp to "the size of its actual content". The deeper into the chapter, the more is clamped away. Concretely, at container 800pt and a 20000pt chapter, a reader at offset 15000 pinching to 3x asks for offset 45800 and is clamped to 19200. This is an ordering problem, and SwiftUI has no equivalent of UIKit's `contentOffsetAdjustment` to express the ordering with.
2. **Discrete zoom steps were proposed as the fix, and would only have lowered the dose.** The same reader pinching to 1.3x asks for 19620 and is clamped to 19200 — 420pt instead of 26600pt. Smaller steps hide it in the middle of a chapter and it returns at the bottom, where the reader least wants it. Quantising the value does not address an ordering problem.

A second, independent defect in the same model: because the live transform had to be expressed as a **ratio** against the committed layout (`rubberBanded(zoomScale × liveMagnification) / zoomScale`), that ratio is below 1 for the whole duration of any zoom-out gesture, so the entire viewport was genuinely drawn smaller with background showing around it. Both defects trace to the same root — the layout width is a moving baseline, and the reader's position is a pixel offset against it.

**The research that settled the replacement** is `.scratch/reader-zoom/research-scroll-anchoring-and-zoom.md`. Aidoku, Mihon and Kotatsu all avoid re-laying-out the list under zoom; only PDFKit genuinely re-lays out, and it can afford to only because it carries position as `(page, point in page space)` rather than as a pixel offset. The summary table's verdict on this app — "in PDFKit's column for layout and in nobody's column for position" — is exactly the defect above.

**What was wrong about the earlier reasoning, and worth not repeating:**

- `.scaleEffect` was rejected on the grounds that "the scroll view would never learn the content became larger and no horizontal scrolling would exist". True, but it is not an argument against the model — no production reader gets panning for free either; Mihon and Kotatsu both hand-roll it. The cost was real and the conclusion drawn from it was not.
- Sharpness was assumed to favour re-layout. `AuthorizedAsyncImage` decodes with `UIImage(data:)` at full source resolution and never downsamples, so the bitmap is 900px wide either way and re-laying out re-decodes nothing at a higher resolution. There is nothing higher to decode.

### Defects found by `/code-review` in the rejected implementation

Recorded because they document real properties of the Reader, two of which still apply:

1. **Pages would have been laid out at 900pt on a 393pt phone.** A scroll view with a horizontal axis proposes an *unspecified* width to its content, and a page sized `maxWidth: .infinity` answers that with its ideal width — the source image's own. Not applicable to the new model, which has no horizontal axis, but it is the reason any future two-axis experiment must impose a width.
2. **The pinch was not anchored at the focal point** — it used the top of the viewport and never read the gesture's own anchor. Still applies.
3. **The strip snapped sideways on release**, because the commit corrected the vertical offset only. Dissolved with the commit.
4. **Rotating while magnified threw the reader through the chapter**, since a container resize rescales the strip exactly as a pinch does. Dissolved with the layout dependency on container width.

Two review findings were deliberately not acted on, and are now moot: `readerPassedBottom`'s `isScrollDriven:` parameter wanting a rename, and the three geometry values at its call sites being a data clump. Both were declined to avoid editing the auto-advance tests; the new model touches neither.
