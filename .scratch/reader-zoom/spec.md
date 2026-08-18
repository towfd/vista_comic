Status: ready-for-agent

# Reader zoom: make small lettering readable without leaving the page

## Problem Statement

The Reader shows every Page at exactly one size — the full width of the screen — and there is no way to change it. A Page is laid out to fill the screen width at its natural aspect ratio, and nothing in the Reader reads a scale factor of any kind.

For a reader learning the language, that fixed size is the binding constraint. Some titles letter their dialogue small, and small Vietnamese text with diacritics is exactly the case where a few pixels decide whether a character is legible. The app already answers "what does this sentence mean" — select, recognize, translate, explain. It does not answer the question that comes first: **can you see it well enough to decide you want to ask?**

The ceiling is worth stating plainly, because it shapes what this feature can honestly promise. Every Page in the library is **900px wide**. An iPhone 16 Pro Max renders that across 430pt at 3x — **1290 device pixels** — so at today's fixed size the image is already being upscaled 1.43x. Magnifying further increases angular size, which genuinely helps legibility, but it adds no detail: at 3x the source is stretched 4.3x and pixel edges are visible. This feature makes text **bigger**, not **sharper**, and the upper bound is chosen with that in mind.

## Solution

Pinch to zoom the **whole vertical strip**, webtoon-style, from 1.0x (today's exact appearance) up to 3.0x.

The zoom is not a per-page effect. Once the reader zooms, scrolling continues normally and every subsequent Page stays at the same magnification — reading does not have to be re-established page by page. The reader returns to full-width by pinching back in; the scale clamps at 1.0 so "back to normal" is the natural bottom of the gesture rather than a control to find. Opening a different chapter resets to 1.0.

Zoom is implemented as an **absolute transform over the viewport**, and the layout never changes. The pages stack stays laid out at `containerWidth` at every magnification; the magnification lives only in the rendering layer, as a `.scaleEffect` of the absolute scale `s` over `1.0...3.0`. The scroll view therefore never learns that zoom exists — `contentOffset`, `contentSize` and `containerSize` hold the same values at 3x as at 1.0, and the reader's position is always a coordinate in the unmagnified strip. The magnification is a lens over a map that is never redrawn, not a bigger map.

That invariance is what everything else is bought with. Because content size cannot change with scale, there is no offset to correct when a zoom is committed — there is no commit — none to correct when the device rotates, and no second way for the three numbers behind the bottom-edge inference to lie. `reservedPageHeight(width:recordedHeightRatio:chapterHeightRatio:)` is untouched for the same reason: the width it is asked about is constant.

One thing is not inherited and has to be built: **panning**. The strip never becomes genuinely wider, so the scroll view has no horizontal axis to give away, and at scale `s` only `1/s` of the viewport is on screen. Horizontal movement is therefore a transform offset the Reader owns and clamps itself, driven by the horizontal component of a one-finger drag while the scroll view keeps the vertical one.

Vertical movement stays with the scroll view, with one exception: at the two ends of a chapter scrolling runs out before the magnified band has covered the first and last screen of content. There the same offset takes over — but **derived from the scroll position rather than driven by a finger**. Mihon (`zoomScrollBy`) and Kotatsu (clamped `translationX`/`translationY`) both make the reader hold a drag to see the end of a chapter; deriving it instead simply shows them, and removes the arbitration that would otherwise have to decide mid-drag whether a vertical movement belongs to the scroll view or to the transform. The cost is that the shift has to decay as scrolling takes over, so content travels slightly faster than the finger over that stretch — `1 + 1/factor`, tuned to 1.4x.

**Selection keeps working at any magnification.** The crop mathematics need no change at all. SwiftUI maps gesture coordinates back through the transform, so the selection overlay's `GeometryReader` and the drag inside it both speak the unmagnified display frame that `SelectionCropMapping.cropRect` already expects. One thing does break and must be fixed — the "drag here to cancel" badge is positioned from `proxy.bounds(of: .scrollView)`, which under this model reports the whole unmagnified viewport rather than the `1/s` band actually on screen, so the badge can be placed where the reader cannot reach it. It is derived from the scale and the pan offset instead.

No backend, API, or model change is required.

## User Stories

1. As a reader, I want to pinch to enlarge the page, so that small lettering becomes legible without leaving the reader.
2. As a reader, I want the magnification to stay as I scroll to the next page, so that I set it once per reading session rather than once per page.
3. As a reader, I want pinching back in to return to the normal full-width view, so that I never need to hunt for a reset control.
4. As a reader, I want the zoom to stop at full width, so that I cannot accidentally shrink the page smaller than the screen.
5. As a reader, I want a sensible upper limit, so that I cannot land on a view so magnified it is only coloured blocks.
6. As a reader, I want the pinch to track my fingers smoothly, so that zooming does not feel like the app is struggling.
7. As a reader, I want the page to become crisp when I let go, so that the magnified view is as good as the source allows.
8. As a reader, I want to zoom centred on what I am pinching at, so that the panel I am interested in stays under my fingers.
9. As a reader zoomed in, I want to drag sideways to see the rest of the page, so that magnification does not hide half the panel.
10. As a reader zoomed in, I want to keep scrolling down normally, so that magnification does not interrupt reading.
11. As a reader zoomed in, I want my horizontal position kept as I scroll down, so that a column of dialogue stays in view.
12. As a reader, I want the app never to jump me into the next chapter because I zoomed, so that changing magnification is not a navigation action.
13. As a reader, I want a chapter never to be marked read because I zoomed out, so that my reading history stays truthful.
14. As a reader, I want pull-past-the-bottom auto-advance to work exactly as before at normal size, so that this feature costs me nothing I already had.
15. As a reader, I want to select text for recognition while zoomed in, so that reading small text and looking it up are one continuous action.
16. As a reader selecting while zoomed, I want the cancel badge to be visible and reachable, so that I can abort a selection at any magnification.
17. As a reader, I want a crop taken while zoomed to recognize exactly as well as one taken at normal size, so that magnification does not degrade recognition.
18. As a reader, I want tapping to show and hide the controls to feel exactly as immediate as it does today, so that adding zoom does not make the rest of the reader sluggish.
19. As a reader, I want my reading position to keep being saved while zoomed, so that resuming works the same however I was reading.
20. As a reader, I want opening a different chapter to start at normal size, so that each chapter begins from a predictable state.
21. As a reader, I want scrolling while zoomed to stay smooth on a long chapter, so that magnification does not make the reader stutter.
22. As a reader who rotates the device or resizes the window, I want the magnified view to stay coherent, so that the page does not end up mis-sized.
23. As a developer, I want the zoom rules testable without rendering the reader, so that the clamping and the auto-advance interlock can be verified quickly.
24. As a reader zoomed in at the start or the end of a chapter, I want to reach the first and last screen of content, so that magnification does not hide the beginning or the ending.
25. As a reader who read a whole chapter while magnified, I want it marked as read, so that my history is truthful whatever size I read at.
26. As a reader pinching out, I want the reader never to be drawn smaller than my screen, so that zooming out never looks like the app is shrinking away.

## Implementation Decisions

### The seams: none are added

This feature introduces **no new injectable seam**. The Reader already keeps everything it derives from scrolling as free functions rather than methods, specifically so they can be verified without rendering it — the past-the-bottom inference, the reported progress page, the start index, the reserved page height and the median height ratio are all already testable that way. Every rule zoom introduces belongs in that same layer: clamping, the pan offset and its bounds, the focal point's conversion into a scroll-offset delta, and the visible band the cancel badge is placed in.

Zoom itself carries **no state machine**. The scale and the pan offset are two values, and every question asked of them — is this position reachable, where does the focal point put the offset, is the badge on screen — is a pure function of those two plus the container size. That is the difference the model change buys: the previous design needed a four-field gate that tracked gesture and scroll phases in order to know when its own geometry could be trusted, and this one has nothing to distrust.

### Zoom is an absolute transform, and the layout is invariant

A single `@State` scale on `ReaderView`, ranging over `1.0...3.0`, is applied as `.scaleEffect(scale, anchor:)` over the pages viewport. The `LazyVStack` keeps being laid out at `containerWidth`; there is no second scroll axis, no imposed content width, and no re-layout when a gesture ends. The scale is **absolute**, not a ratio against some previously committed layout, and that is what makes it structurally impossible for the rendered viewport to become *smaller* than the reader's screen.

**The layout-width model this spec originally specified was built, device-tested, and rejected.** It laid the strip out at `containerWidth × scale` inside a two-axis scroll view and committed the new width when the fingers lifted. Two defects follow from that commit, and neither is fixable within the model:

- **The reader was thrown through the chapter at the instant the fingers lifted.** Committing a new width changes content size, so the scroll offset has to be re-anchored — but the assignment is evaluated against the *pre-growth* content size, and `scrollTo(point:)` is documented to clamp to "the size of its actual content". The deeper into the chapter the reader was, the more was clamped away. This is an ordering problem rather than a race that reordering statements can win, and SwiftUI has no equivalent of UIKit's `contentOffsetAdjustment` to express the ordering with.
- **Pinching out shrank the whole reader.** With a committed layout as the baseline, the live transform has to be expressed as a *ratio* against it, and that ratio is below 1 for the entire duration of any zoom-out gesture — so the viewport was genuinely drawn smaller, with background showing around it.

Bridging to `UIScrollView` through `UIViewRepresentable` remains rejected for the reason it always was: it would take `.scrollPosition`, `.onScrollGeometryChange`, `.onScrollPhaseChange` and the whole of the progress, prefetch and auto-advance machinery with it. Research into how production readers solve this (`research-scroll-anchoring-and-zoom.md`) found that Aidoku, Mihon and Kotatsu all avoid re-laying-out the list under zoom; only PDFKit genuinely re-lays out, and it can afford to only because it carries position as `(page, point in page space)` rather than as a pixel offset.

### The gesture, and what happens during it

- `MagnifyGesture`, attached so it composes with the scroll view's own panning rather than replacing it.
- The scale is applied continuously at the gesture's focal point, and **nothing is committed when the fingers lift** — the value the gesture settles on is simply the value the transform keeps. There is no re-layout, and so there is no moment at which the reader can be displaced.
- Scale is clamped to `1.0...3.0`. Both bounds rubber-band during the gesture and settle at the bound. The rubber-band below 1.0 is expressed as resistance only: the rendered scale is never allowed below 1.0, because a viewport smaller than the screen is not a state this reader has.
- **The focal point's vertical component is resolved by scrolling, not by the transform.** The transform's vertical anchor is fixed, and the vertical part of "keep what is under the fingers under the fingers" is applied as a change to the scroll offset, so that the reader has one vertical mechanism rather than two. That offset change is safe in a way the old commit was not: content size never changed, so it cannot be clamped against a stale one.
- Panning is clamped to the magnified content — horizontally at every position, vertically only where the scroll view has run out, which is the first and last screen of a chapter.
- There is no double-tap gesture, no reset button, and no discrete zoom steps. `ComicView`'s existing single-tap-to-toggle-controls therefore keeps firing immediately, with no double-tap disambiguation delay.
- The horizontal pan offset is preserved while scrolling vertically, so a column of dialogue stays in view from page to page.

### The bottom-edge inferences

`readerPassedBottom` decides "the reader pulled past the end" from content offset, content height and container height. Under this model zoom cannot affect any of the three, so the arm/disarm state machine the layout-width model needed — disarm on a pinch, re-arm only on a genuine one-finger drag, stay disarmed while the committed scale is not 1.0 — is deleted. What remains is the pre-existing discipline from PR #65: the inference is trusted only while the scroll view is being driven by the reader. That gate exists for the keyboard-collapse case, is unrelated to zoom, and stays exactly as it is.

The two consumers are then decided separately, because nothing forces them to agree any more:

- **Read detection is restored at every scale.** A chapter read to its end while magnified is marked `read`. The old accepted consequence — that it stayed `reading` — was a symptom of the layout-width model rather than a decision, and it is removed.
- **Auto-advance stays inert while the scale is not 1.0.** This is a product rule, not a technical limitation: a reader who has magnified a panel is examining it, and a chapter change is not something they should be able to trigger without returning to full width first. It is a single scale check, not a state machine.

### Selection at magnification

- `SelectionCropMapping`, `produceCrop` and the overlay's drag handling are unchanged, and so are their tests. Gesture coordinates arrive already mapped back through the transform, so the overlay's `GeometryReader` reports the unmagnified display frame and the drag is expressed in that same space — which is exactly the space the mapping already documents.
- The cancel badge's visible region is the one thing that changes. `proxy.bounds(of: .scrollView)` reports the whole unmagnified viewport under this model rather than the `1/s` band on screen, so the badge's frame is derived from the scale and the pan offset instead.
- The existing `scrollDisabled(isSelecting)` behaviour is kept as is. While selecting, the reader cannot pan; they position the page first, then enter selection mode. This is accepted for v1.

### Reset

The scale returns to 1.0 whenever the chapter changes — the same boundary the chapter's page load already hangs off — and whenever the Reader is dismissed. Nothing is persisted: no `UserDefaults`, no per-comic memory, no store of any kind.

## Testing Decisions

Everything decidable without a view should be a pure function tested directly, following how `ReaderAutoAdvanceGateTests` and `ReservedPageHeightTests` already cover this Reader's logic:

- Clamping: a gesture value below the minimum yields 1.0, above the maximum yields 3.0, inside the range passes through — and the rendered scale is never below 1.0 even mid-rubber-band.
- The pan offset is clamped to the magnified content: no slack at all at 1.0, `(s − 1)` viewports of horizontal slack at scale `s`, and no position outside that range reachable.
- The end-of-chapter shift is zero at full width and zero mid-chapter, and at either end is exactly the pan limit — enough to put the chapter's first or last screen against the screen edge, asserted as that property rather than as a number.
- The shift decays monotonically as scrolling takes over, with no step large enough to read as a jolt.
- The focal point's vertical component converts to a scroll-offset delta that puts the same content coordinate back under the same viewport point.
- Read detection is armed at every scale, and auto-advance is armed only at 1.0 — asserted as two separate questions, since this is the one place they deliberately disagree.
- The existing auto-advance gate tests keep passing unchanged: PR #65's scroll-driven discipline is not what this feature touches.
- The cancel-zone frame is inside the visible band across a range of scales and pan offsets.
- Existing `SelectionCropMappingTests` must continue to pass **untouched, and without new cases** — under this model the mapping never sees a magnified frame, so a case asserting one would pin a state that cannot occur.

**No XCUITest is written for this feature**, per `CLAUDE.md`'s verification rules. UI-facing behaviour is handed off as an explicit on-device checklist covering: pinching in and out, confirming the clamp at both ends and that the reader is never drawn smaller than the screen; that nothing moves at the instant the fingers lift; panning to the edges of a magnified page; reaching the first and last screen of a chapter while magnified; scrolling several pages while zoomed; selecting and recognizing text at 2x and 3x; reaching the cancel badge while zoomed; rotating while zoomed; and one compact-phone plus one larger-phone layout.

## Out of Scope

- **Per-page zoom.** Considered first and rejected by the repo owner: re-establishing magnification on every page is the annoyance the feature exists to remove.
- **A separate full-screen zoom viewer.** Same reason — it makes magnification a mode to enter and leave rather than a property of reading.
- **Discrete zoom steps** (1.0 / 1.3 / 1.5 / …), whether snapped to on release or cycled by a control. Considered as a fix for the layout-width model's displacement and rejected: quantising the value does not address an ordering problem, it only lowers the dose, and it stops helping again deep in a long chapter. Under this model there is nothing left for it to fix.
- **Double-tap to zoom, and any control-bar zoom affordance.** Deliberately excluded so the existing single tap keeps toggling the controls without a disambiguation delay.
- **Persisting the scale across chapters, across reader sessions, or across launches.** Decided against; each chapter starts at full width.
- **Panning while in selection mode.**
- **Auto-advancing while magnified.** A deliberate product rule rather than a limitation — see the bottom-edge inferences above.
- **Higher-resolution source images.** The 900px width is the real ceiling on sharpness, but changing it means changing the library, the scanner and the media endpoints — a different project entirely. Nothing here should be built on the assumption that it will happen.
- **Downsampling or re-decoding images at the zoomed size.** `PageImageCache` already decodes at full source resolution because the crop path depends on it; that stays.
- **Exact page heights from the backend** (`.scratch/page-dimensions/`), which is parked — see Further Notes.
- **Any change to progress reporting, prefetching, retention, or comprehension behaviour.**

## Further Notes

Measured, not assumed — re-measure if the library's character changes:

- Pages are 900px wide (spot-checked across the library; consistent with the 1855-page measurement recorded for `reader-page-prefetch`).
- iPhone 16 Pro Max: 430pt at 3x = 1290 device pixels, so full-width display is already a 1.43x upscale. iPhone SE: 375pt at 2x = 750 pixels, slightly under the source.
- Consequently 2x ≈ 2.9x source upscale and 3x ≈ 4.3x. The cap is a legibility judgement, not a technical limit.
- **Sharpness is not a reason to prefer either zoom model here.** `AuthorizedAsyncImage` decodes with `UIImage(data:)` at full source resolution and never downsamples, so the bitmap in memory is 900px wide whichever model is used. Re-laying out at a larger width does not re-decode at a higher resolution, because there is nothing higher to decode. At most the transform model costs one extra resampling step, and Core Animation may not produce even that.

**What the device pass established, and what it corrected.** Reading on a device at 1.0 and again at 3x, through pages that had not been loaded yet, produced no observable displacement in either case. The displacement the repo owner had reported was reproducible only at the instant the fingers lifted from a pinch — the layout-width commit — and that observation is what decided this rewrite.

That matters beyond zoom. `.scratch/page-dimensions/` was specified on the premise that the reported jumping came from the Reader's height estimate, and that zoom had taken an already-known problem from tolerable to unusable. **That attribution was wrong.** The height-estimate work is parked, and `reader-page-prefetch` ticket 03's original decision to close it — on the evidence that prefetching made the residual shift unnoticeable — stands unchallenged. Revisit it only if displacement is observed after this rewrite, and specifically while scrolling faster than pages can load, which is the one condition prefetching does not cover.

Two risks to watch during implementation, both in the panning:

- **Gesture arbitration.** A one-finger drag has to feed the scroll view vertically and the pan horizontally at the same time, and has to hand the vertical over to the pan when the scroll view reaches either end. Reading `ReaderScrollMetrics` is what makes that decidable. This is the part most likely to need iteration, and the symptoms of getting it wrong are a pan that steals a scroll, and a chapter end that feels stuck rather than panned.
- **Anchoring during the pinch.** The focal point's vertical component travels through the scroll offset while its horizontal component travels through the pan, so two mechanisms have to agree. The symptom of getting it wrong is content drifting diagonally away from the fingers.

The zoom feature and `.scratch/offline-download/` are independent and can be built in either order. They meet at exactly one point: the offline disk layer sits inside the image cache, below `AuthorizedAsyncImage`, so a zoomed page and a normal page load through the same path and the Reader never learns which one it got.