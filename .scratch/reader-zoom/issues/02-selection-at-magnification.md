# 02 — Selection works at any magnification

**What to build:** Reading small lettering and asking what it means are the same errand. A reader who has just magnified a panel to read it should be able to select that sentence and send it through recognition and translation without first returning to full width — otherwise every lookup costs a re-zoom, which is exactly the friction magnification was added to remove.

The crop mathematics need no change and must not be changed. The mapping from an on-screen selection to source pixels is a pure function of the container size and the source image's pixel size, and because zoom is a real layout change rather than a rendering transform, the geometry reported inside the selection overlay is already the enlarged size. A selection drawn over the same visible region at 3x must therefore produce the same source-pixel rectangle as one drawn at 1.0 — and a test should say so, because this is the property that makes recognition quality independent of magnification.

**One thing genuinely breaks and is the substance of this ticket.** The "drag here and release to cancel" badge is positioned relative to the Page's own display frame, near its top-right corner. At 3x that corner sits roughly two screen widths off to the right, so mid-drag cancellation — a single continuous touch that aborts without producing a crop — becomes unreachable at exactly the magnifications where a reader is most likely to be selecting carefully. The badge is re-anchored to the **visible viewport** so it is on screen at every scale and every horizontal offset, while keeping its current behaviour: it appears only once a drag is in progress, confirms visually when the finger is inside it, and cancels on release.

Selection mode continues to disable scrolling while active, which means a reader cannot pan while selecting: they position the Page first, then enter selection mode. That is accepted for this version and is not a defect to fix here.

**Blocked by:** 01 — Pinch to zoom the strip, without breaking auto-advance.

**Status:** implemented, awaiting device verification (branch `feat/reader-zoom`)

Build succeeds on iPhone 16 Pro Max and iPhone SE (3rd generation); 229 unit tests pass, none failing.

**`/code-review` found one real defect, fixed before this line was written.** The badge was placed at the top of the visible region — which is exactly where the reader's own control bar is, and selection mode forces that bar visible. It would have been positioned correctly and still been invisible underneath opaque material: a different failure from being off screen, and just as complete. The badge is now held clear of the bar, whose height is measured rather than assumed so it survives Dynamic Type.

The crop mathematics were left untouched, as intended, and a test now says why that is safe rather than leaving it as an assumption: the display frame the mapping is handed grows with the magnification and so do the drag coordinates drawn in it, so the same visible region selected at 2x and 3x produces the same source-pixel rectangle as at full width.

The badge is now anchored to the top-right of whatever part of the page is visible, which is a change in **both** axes. The horizontal half is the one the ticket described; the vertical half matters just as much, because at 3x a page is several screens tall and a badge pinned to the page's top is off screen whenever the reader is looking at the middle of it.

**The one thing to check first on device.** The visible region comes from asking the page's geometry for the scroll view's bounds in its own coordinate space. If that returns something other than the visible rect, the function falls back to the page's own corner — which is exactly today's behaviour, i.e. the bug this ticket fixes, silently. So the first check is simply: **at 3x, is the badge on screen?** If it is not, the fallback is being taken and the cause is that lookup, not the geometry maths, which the tests cover.

**Verify on device:**

- Enter selection mode at 2x and at 3x, drag a selection over a speech bubble, and confirm recognition and translation behave exactly as at full width.
- At 3x, panned to the left edge, mid-page: the cancel badge must be on screen. Repeat panned to the right edge and near the top and bottom of a tall page.
- Drag into the badge and release, at 3x: the selection must be abandoned with no result sheet, and selection mode must stay on.
- Complete a real selection at 3x: the result sheet appears and selection mode ends itself.
- Select the same speech bubble at full width and at 3x and compare the recognized text — it should be the same, since the crop is the same pixels.
- Confirm selection at full width still works on both a compact and a large phone. Note that the badge deliberately moves here too: on a page taller than the screen it now follows the visible region rather than sitting at the page's top, where it was previously off screen whenever you were reading the middle of a tall page. That is the same criterion — "visible and reachable at every scale" — applied at 1.0.
- Selection mode is a one-finger drag and zoom is two fingers, so they do not fight. If you do pinch while selection mode is on, the badge's position will be stale until you let go; that is an untested edge and worth a glance.
- Panning while selection mode is on is still deliberately not possible; position the page first, then enter selection mode.

- [ ] Selection mode can be entered and used at any scale, including 3x
- [ ] The cancel badge is visible and reachable within the visible viewport at every scale and every horizontal offset
- [ ] Dragging into the badge and releasing cancels the selection, exactly as it does at 1.0
- [ ] A drag that produces no crop — the cancel zone, or a selection off the Page — leaves selection mode active, as today
- [ ] A selection over a given visible region while magnified produces the same source-pixel crop as the same visible region at 1.0
- [ ] Recognition, translation and comprehension for a crop taken while magnified behave identically to one taken at full width
- [ ] Selection mode still ends itself once a crop has been produced
- [ ] Leaving selection mode mid-drag discards the partial selection, as today
- [ ] Existing selection-crop mapping tests pass unchanged, with a new case covering an enlarged display frame
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering selecting and recognizing at both 2x and 3x
