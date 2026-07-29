# 03 — Reader selection-mode UI crops the live page image

**What to build:** the Reader gains an explicit selection mode, entered/exited via a control (following the existing `controlsOverlay` button pattern), distinct from the current tap-to-toggle-controls gesture. While in selection mode, dragging draws a visible rectangle over the current page; releasing runs the coordinate mapping from Ticket 02 against the decoded image exposed in Ticket 01, producing a real crop of the source pixels, shown back to the user for confirmation. Cancelling an in-progress selection before release produces no crop. No recognition yet — this ticket is demoable purely as "the crop shown is visibly the right region, at full source quality."

**Blocked by:** 01, 02

**Status:** resolved (commit `ba2a36e` on `feat/ocr-recognition-foundation`)

- [x] Reader gains a control to enter/exit selection mode without disrupting the existing scroll gesture or the tap-to-toggle-controls gesture — `.scrollDisabled(isSelecting)` + a guard on the existing tap gesture; verified by code inspection only (see Comments)
- [x] Dragging in selection mode draws a visible rectangle tracking the gesture — verified by code inspection only
- [x] Releasing produces and displays the cropped source-pixel region (not a screenshot of the scaled on-screen rendering) — **verified by running**: `ReaderSelectionCropTests` reproduces the exact Ticket 01→02→crop pipeline against a real decoded quadrant-colored PNG and asserts exact pixel dimensions and RGBA content
- [x] Cancelling an in-progress selection before release discards it — no crop is produced — implemented via a drag-into-corner-badge gesture (see Comments for why, not a mid-drag tap); verified by code inspection only
- [ ] Verified on at least one compact iPhone layout and one larger iPhone layout — not done; no interactive simulator session was available in the implementation environment

## Comments

Cancel UX deviates from this ticket's literal phrasing ("an × button near the rectangle while dragging"): that's not achievable with one continuous touch — tapping a separate button requires lifting the finger driving the `DragGesture`. Implemented instead as a fixed 44pt "release-here-to-cancel" zone anchored at the page's top-trailing corner, highlighted while the drag is inside it; releasing there discards the selection with no crop. Still satisfies "cancel before release, no crop produced" within a single touch.

Verification gap: the interactive gesture/UI (drag-to-draw, the mode-toggle button, layout on compact vs. larger iPhones) was reasoned correct from the code (geometry-driven via `GeometryReader`, not hardcoded) but not exercised in a live simulator session — flag for manual check before considering this fully done, per CLAUDE.md's verification checklist. The crop pipeline itself (the part most likely to have a real correctness bug) is the part that got real automated verification.

No hand-off point yet for the confirmed crop — `CroppedSelectionPreview` is dismiss-only. Ticket 05 decides how it reaches `OCRRecognizer`.
