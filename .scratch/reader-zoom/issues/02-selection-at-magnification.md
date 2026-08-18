# 02 — Selection works at any magnification

**What to build:** Reading small lettering and asking what it means are the same errand. A reader who has just magnified a panel to read it should be able to select that sentence and send it through recognition and translation without first returning to full width — otherwise every lookup costs a re-zoom, which is exactly the friction magnification was added to remove.

The crop mathematics need no change and must not be changed. The mapping from an on-screen selection to source pixels is a pure function of the display frame size and the source image's pixel size, and because zoom is a transform over the viewport, SwiftUI maps gesture coordinates back through it — so the overlay's `GeometryReader` and the drag inside it both speak the **unmagnified** display frame, which is exactly the space the mapping already documents. A selection drawn over the same visible region at 3x must therefore produce the same source-pixel rectangle as one drawn at 1.0, for the same reason it does today: the mapping never learns that magnification happened.

**One thing genuinely breaks and is the substance of this ticket.** The "drag here and release to cancel" badge has to sit inside the part of the Page the reader can actually see, and under this zoom model nothing in the view hierarchy reports that region. `proxy.bounds(of: .scrollView)` returns the whole **unmagnified** viewport, while what is on screen at scale `s` is a `1/s` band of it positioned by the pan offset — so a badge placed from that lookup can land off screen at exactly the magnifications where a reader is most likely to be selecting carefully. The visible region is therefore **derived from the scale and the pan offset** rather than looked up, while the badge keeps its current behaviour: it appears only once a drag is in progress, confirms visually when the finger is inside it, and cancels on release.

Selection mode continues to disable scrolling while active, which means a reader cannot pan while selecting: they position the Page first, then enter selection mode. That is accepted for this version and is not a defect to fix here.

**Blocked by:** 01 — Pinch to zoom the strip, without breaking auto-advance.

**Status:** done — device-verified by the repo owner, 2026-08-18; merged in PR [#66](https://github.com/towfd/vista_comic/pull/66)

**What the rework turned out to be.** One derived value, as predicted. `ReaderZoom.visibleRegion(inViewport:scale:pan:)` computes the `1/s` band the transform actually puts on screen, and the overlay hands that to `selectionCancelZoneFrame` in place of the raw `proxy.bounds(of: .scrollView)`. It returns the viewport unchanged at full width, so behaviour at 1.0 is bit-for-bit what it was. The scale passed in is the *settled* one rather than the live one — a pinch in flight would otherwise invalidate every realised row on every frame, and panning is disabled while selecting, so the badge only has to be right once the fingers are off. `SelectionCropMapping`, `produceCrop`, the overlay's drag handling and every one of their tests are untouched.

Builds on iPhone 16 Pro Max and iPhone SE (3rd generation); 231 unit tests pass, none failing.

Everything below this line was written against the rejected layout-width model and is kept for the reasoning it records; where it says the display frame grows with magnification, it no longer does.

**`/code-review` found one real defect, fixed before this line was written.** The badge was placed at the top of the visible region — which is exactly where the reader's own control bar is, and selection mode forces that bar visible. It would have been positioned correctly and still been invisible underneath opaque material: a different failure from being off screen, and just as complete. The badge is now held clear of the bar, whose height is measured rather than assumed so it survives Dynamic Type.

The crop mathematics were left untouched, as intended, and a test now says why that is safe rather than leaving it as an assumption: the display frame the mapping is handed grows with the magnification and so do the drag coordinates drawn in it, so the same visible region selected at 2x and 3x produces the same source-pixel rectangle as at full width.

The badge is now anchored to the top-right of whatever part of the page is visible, which is a change in **both** axes. The horizontal half is the one the ticket described; the vertical half matters just as much, because at 3x a page is several screens tall and a badge pinned to the page's top is off screen whenever the reader is looking at the middle of it.

**The one thing to check first on device.** The visible region is now computed from the scale and the pan offset rather than looked up, so the silent-fallback failure the old implementation could take no longer exists. The first check is still the same one: **at 3x, panned to an edge, is the badge on screen?** If it is not, the cause is the derivation, which is a pure function and should be pinned by a test before the device is involved.

**Verify on device:**

- Enter selection mode at 2x and at 3x, drag a selection over a speech bubble, and confirm recognition and translation behave exactly as at full width.
- At 3x, panned to the left edge, mid-page: the cancel badge must be on screen. Repeat panned to the right edge and near the top and bottom of a tall page.
- Drag into the badge and release, at 3x: the selection must be abandoned with no result sheet, and selection mode must stay on.
- Complete a real selection at 3x: the result sheet appears and selection mode ends itself.
- Select the same speech bubble at full width and at 3x and compare the recognized text — it should be the same, since the crop is the same pixels.
- Confirm selection at full width still works on both a compact and a large phone. Note that the badge deliberately moves here too: on a page taller than the screen it now follows the visible region rather than sitting at the page's top, where it was previously off screen whenever you were reading the middle of a tall page. That is the same criterion — "visible and reachable at every scale" — applied at 1.0.
- Selection mode is a one-finger drag and zoom is two fingers, so they do not fight. If you do pinch while selection mode is on, the badge's position will be stale until you let go; that is an untested edge and worth a glance.
- Panning while selection mode is on is still deliberately not possible; position the page first, then enter selection mode.

- [x] Selection mode can be entered and used at any scale, including 3x
- [x] The cancel badge is visible and reachable within the visible viewport at every scale and every horizontal offset
- [x] Dragging into the badge and releasing cancels the selection, exactly as it does at 1.0
- [x] A drag that produces no crop — the cancel zone, or a selection off the Page — leaves selection mode active, as today
- [x] A selection over a given visible region while magnified produces the same source-pixel crop as the same visible region at 1.0
- [x] Recognition, translation and comprehension for a crop taken while magnified behave identically to one taken at full width
- [x] Selection mode still ends itself once a crop has been produced
- [x] Leaving selection mode mid-drag discards the partial selection, as today
- [x] Existing selection-crop mapping tests pass unchanged, **and without new cases** — under this zoom model the mapping never sees an enlarged display frame, so a case asserting one would pin a state that cannot occur
- [x] The visible region the badge is placed in is a pure function of the scale and the pan offset, with its own unit tests, rather than a geometry lookup that can silently fall back
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering selecting and recognizing at both 2x and 3x
