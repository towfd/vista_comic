Status: ready-for-agent

# Reader zoom: make small lettering readable without leaving the page

## Problem Statement

The Reader shows every Page at exactly one size — the full width of the screen — and there is no way to change it. A Page is laid out to fill the screen width at its natural aspect ratio, and nothing in the Reader reads a scale factor of any kind.

For a reader learning the language, that fixed size is the binding constraint. Some titles letter their dialogue small, and small Vietnamese text with diacritics is exactly the case where a few pixels decide whether a character is legible. The app already answers "what does this sentence mean" — select, recognize, translate, explain. It does not answer the question that comes first: **can you see it well enough to decide you want to ask?**

The ceiling is worth stating plainly, because it shapes what this feature can honestly promise. Every Page in the library is **900px wide**. An iPhone 16 Pro Max renders that across 430pt at 3x — **1290 device pixels** — so at today's fixed size the image is already being upscaled 1.43x. Magnifying further increases angular size, which genuinely helps legibility, but it adds no detail: at 3x the source is stretched 4.3x and pixel edges are visible. This feature makes text **bigger**, not **sharper**, and the upper bound is chosen with that in mind.

## Solution

Pinch to zoom the **whole vertical strip**, webtoon-style, from 1.0x (today's exact appearance) up to 3.0x.

The zoom is not a per-page effect. Once the reader zooms, scrolling continues normally and every subsequent Page stays at the same magnification — reading does not have to be re-established page by page. The reader returns to full-width by pinching back in; the scale clamps at 1.0 so "back to normal" is the natural bottom of the gesture rather than a control to find. Opening a different chapter resets to 1.0.

Zoom is implemented as a **change of layout width**, not as a rendering transform. The strip is laid out at `containerWidth × scale` inside a scroll view that scrolls both axes, so the pages genuinely become wider and — because they are `.fit` at a fixed aspect ratio — proportionally taller. Everything the Reader already derives from its scroll view keeps working natively: `.scrollPosition`, `.onScrollGeometryChange`, `.onScrollPhaseChange`, and per-row `onAppear`/`onDisappear` visibility tracking. `reservedPageHeight(width:recordedHeightRatio:chapterHeightRatio:)` is already parameterised by width and needs no change at all.

Two behaviours have to be actively defended rather than inherited.

**The bottom-edge inferences are disarmed while zoomed.** `readerPassedBottom` decides "the reader pulled past the end" from content offset, content height and container height. Zooming changes content height by up to 3x, and the dangerous moment is the transition *down*: pinching from 3x back to 1x collapses the content to a third of its height while the scroll offset is still the old, larger value — which satisfies the past-the-bottom test anywhere past the first third of a chapter. That is precisely the class of false trigger `.scratch/reader-auto-advance-false-trigger/` was opened for. Both consumers of the inference (auto-advance, and the reachedEnd detection that marks a chapter read) are therefore inert whenever the scale is not 1.0, and stay inert after the scale returns to 1.0 until a genuine one-finger scroll re-arms them. Content-size clamping produces no new touch, so the re-arm cannot happen by accident.

**Selection keeps working at any magnification.** Reading small text and asking what it means are the same errand, so zoom and selection must coexist. The crop mathematics need no change: `SelectionCropMapping.cropRect` is a pure function of the container size and the source pixel size, and because zoom is a real layout change the `GeometryReader` inside the selection overlay reports the enlarged size automatically. One thing does break and must be fixed — the "drag here to cancel" badge is positioned relative to the *page's* top-right corner, which at 3x sits two screens off to the right. It is re-anchored to the visible viewport so it is reachable at every scale.

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

## Implementation Decisions

### The seams: none are added

This feature introduces **no new injectable seam**. The Reader already keeps everything it derives from scrolling as free functions rather than methods, specifically so they can be verified without rendering it — the past-the-bottom inference, the reported progress page, the start index, the reserved page height and the median height ratio are all already testable that way. Every rule zoom introduces belongs in that same layer: clamping, the laid-out width, the arm/disarm state machine, and the cancel-zone frame.

The one piece with real state — whether the bottom-edge inferences are armed — is a small pure value type that takes gesture and scroll-phase events and answers a single question. It is a unit under test, not a dependency to inject.

### Zoom is a layout width, not a transform

A single `@State` scale on `ReaderView` drives the width the pages stack is laid out at. The pages `ScrollView` gains the horizontal axis; the `LazyVStack` is given `containerWidth × scale` as its width, and each `ReaderPage` inherits that width through the existing `pageWidth` measurement, which is already read from the stack via `.onGeometryChange`.

`.scaleEffect` was considered and rejected as the committed representation: it does not participate in layout, so the scroll view would never learn that the content became larger and no horizontal scrolling would exist. Bridging to `UIScrollView` through `UIViewRepresentable` was also rejected — it would take `.scrollPosition`, `.onScrollGeometryChange`, `.onScrollPhaseChange` and the whole of the progress, prefetch and auto-advance machinery with it, which is a rewrite of the Reader's scroll layer for a feature that does not otherwise need one.

### The gesture, and what happens during it

- `MagnifyGesture`, attached so it composes with the scroll view's own panning rather than replacing it.
- **During** the gesture the strip is transformed (cheap, GPU-resident, tracks the fingers), anchored at the gesture's focal point.
- **On release** the transform is dropped and the final scale is committed as the real layout width, which re-renders the pages crisply at the new size.
- Scale is clamped to `1.0...3.0`. Below 1.0 the gesture rubber-bands and settles back at 1.0; above 3.0 it rubber-bands and settles at 3.0.
- There is no double-tap gesture and no reset button. `ComicView`'s existing single-tap-to-toggle-controls therefore keeps firing immediately, with no double-tap disambiguation delay.
- Horizontal scroll offset is preserved across vertical scrolling; it is the scroll view's own state and is not managed separately.

### The auto-advance interlock

Both `.onScrollGeometryChange` handlers that call `readerPassedBottom` are gated on an armed flag in addition to the existing `isScrollDriven`:

- A magnify gesture beginning **disarms** it.
- It **re-arms** only on a scroll phase transition into `.tracking` that occurs while no magnify gesture is in flight — i.e. a real one-finger drag after the pinch has ended.
- While the committed scale is not 1.0 it stays disarmed regardless.

The re-arm is deliberately a gesture condition, not a timer: a scroll view clamping its offset after the content shrinks emits geometry updates but produces no new touch, so this closes the window structurally rather than by racing it. The rule mirrors what `goTo` already does when it sets `isScrollDriven = false` on a chapter change, and what PR #65 established as this Reader's discipline for geometry-derived conclusions.

The accepted consequence: a chapter read to its end entirely while zoomed is not marked `read` and remains `reading`. Per-page progress is unaffected — it comes from `visiblePages`, not from geometry — so the resume position is still correct.

### Selection at magnification

- `SelectionCropMapping` and `produceCrop` are unchanged. The overlay's `GeometryReader` reports the enlarged display frame, and the drag coordinates are in that same enlarged space, so the mapping stays internally consistent and continues to crop full source pixels.
- `cancelZoneFrame(in:)` is re-anchored to the visible viewport rather than to the page's own display frame, so the badge is on screen at every scale and at every horizontal offset.
- The existing `scrollDisabled(isSelecting)` behaviour is kept as is. While selecting, the reader cannot pan; they position the page first, then enter selection mode. This is accepted for v1.

### Reset

The scale returns to 1.0 whenever the chapter changes — the same boundary the chapter's page load already hangs off — and whenever the Reader is dismissed. Nothing is persisted: no `UserDefaults`, no per-comic memory, no store of any kind.

## Testing Decisions

Everything decidable without a view should be a pure function tested directly, following how `ReaderAutoAdvanceGateTests` and `ReservedPageHeightTests` already cover this Reader's logic:

- Clamping: a gesture value below the minimum yields 1.0; above the maximum yields 3.0; inside the range passes through.
- Laid-out width is the container width multiplied by the committed scale, and equals the container width exactly at 1.0.
- The auto-advance arm/disarm state machine: a magnify start disarms; a `.tracking` phase during a magnify does not re-arm; a `.tracking` phase after it ends does; a committed scale above 1.0 keeps it disarmed whatever else happens.
- `readerPassedBottom` returns `false` for the specific shape of the 3x→1x collapse (large stale offset, content height reduced to a third) whenever the gate is disarmed — the regression test for the failure this feature would otherwise introduce.
- The cancel-zone frame is inside the visible viewport for a range of scales and horizontal offsets.
- Existing `SelectionCropMappingTests` must continue to pass untouched; add a case at an enlarged display frame asserting the same source-pixel rect comes back, since it is the enlarged frame that proves magnification does not shift the crop.

**No XCUITest is written for this feature**, per `CLAUDE.md`'s verification rules. UI-facing behaviour is handed off as an explicit on-device checklist covering: pinching in and out and confirming the clamp at both ends; scrolling several pages while zoomed; zooming out from deep inside a chapter and confirming the reader stays put (the #65 regression); selecting and recognizing text at 2x and 3x; reaching the cancel badge while zoomed; rotating while zoomed; and one compact-phone plus one larger-phone layout.

## Out of Scope

- **Per-page zoom.** Considered first and rejected by the repo owner: re-establishing magnification on every page is the annoyance the feature exists to remove.
- **A separate full-screen zoom viewer.** Same reason — it makes magnification a mode to enter and leave rather than a property of reading.
- **Double-tap to zoom, and any control-bar zoom affordance.** Deliberately excluded so the existing single tap keeps toggling the controls without a disambiguation delay.
- **Persisting the scale across chapters, across reader sessions, or across launches.** Decided against; each chapter starts at full width.
- **Panning while in selection mode.**
- **Higher-resolution source images.** The 900px width is the real ceiling on sharpness, but changing it means changing the library, the scanner and the media endpoints — a different project entirely. Nothing here should be built on the assumption that it will happen.
- **Downsampling or re-decoding images at the zoomed size.** `PageImageCache` already decodes at full source resolution because the crop path depends on it; that stays.
- **Any change to progress reporting, prefetching, retention, or comprehension behaviour.**

## Further Notes

Measured, not assumed — re-measure if the library's character changes:

- Pages are 900px wide (spot-checked across the library; consistent with the 1855-page measurement recorded for `reader-page-prefetch`).
- iPhone 16 Pro Max: 430pt at 3x = 1290 device pixels, so full-width display is already a 1.43x upscale. iPhone SE: 375pt at 2x = 750 pixels, slightly under the source.
- Consequently 2x ≈ 2.9x source upscale and 3x ≈ 4.3x. The cap is a legibility judgement, not a technical limit.

Two risks to watch during implementation. The first is **gesture arbitration**: `MagnifyGesture` composing with a two-axis `ScrollView` is the part most likely to need iteration, and the symptom to watch for is a pinch that either steals a scroll or gets swallowed by one. The second is **commit cost** — re-laying out a 180-page `LazyVStack` at a new width on gesture end. If that proves visible, the correct response is to narrow what is re-laid out, not to fall back to a permanent transform, which would take the scroll view's knowledge of the content size with it.

The zoom feature and `.scratch/offline-download/` are independent and can be built in either order. They meet at exactly one point: the offline disk layer sits inside the image cache, below `AuthorizedAsyncImage`, so a zoomed page and a normal page load through the same path and the Reader never learns which one it got.
