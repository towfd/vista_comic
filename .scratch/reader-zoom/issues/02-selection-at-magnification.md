# 02 — Selection works at any magnification

**What to build:** Reading small lettering and asking what it means are the same errand. A reader who has just magnified a panel to read it should be able to select that sentence and send it through recognition and translation without first returning to full width — otherwise every lookup costs a re-zoom, which is exactly the friction magnification was added to remove.

The crop mathematics need no change and must not be changed. The mapping from an on-screen selection to source pixels is a pure function of the container size and the source image's pixel size, and because zoom is a real layout change rather than a rendering transform, the geometry reported inside the selection overlay is already the enlarged size. A selection drawn over the same visible region at 3x must therefore produce the same source-pixel rectangle as one drawn at 1.0 — and a test should say so, because this is the property that makes recognition quality independent of magnification.

**One thing genuinely breaks and is the substance of this ticket.** The "drag here and release to cancel" badge is positioned relative to the Page's own display frame, near its top-right corner. At 3x that corner sits roughly two screen widths off to the right, so mid-drag cancellation — a single continuous touch that aborts without producing a crop — becomes unreachable at exactly the magnifications where a reader is most likely to be selecting carefully. The badge is re-anchored to the **visible viewport** so it is on screen at every scale and every horizontal offset, while keeping its current behaviour: it appears only once a drag is in progress, confirms visually when the finger is inside it, and cancels on release.

Selection mode continues to disable scrolling while active, which means a reader cannot pan while selecting: they position the Page first, then enter selection mode. That is accepted for this version and is not a defect to fix here.

**Blocked by:** 01 — Pinch to zoom the strip, without breaking auto-advance.

**Status:** ready-for-agent

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
