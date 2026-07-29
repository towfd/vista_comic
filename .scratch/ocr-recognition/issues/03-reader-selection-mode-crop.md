# 03 — Reader selection-mode UI crops the live page image

**What to build:** the Reader gains an explicit selection mode, entered/exited via a control (following the existing `controlsOverlay` button pattern), distinct from the current tap-to-toggle-controls gesture. While in selection mode, dragging draws a visible rectangle over the current page; releasing runs the coordinate mapping from Ticket 02 against the decoded image exposed in Ticket 01, producing a real crop of the source pixels, shown back to the user for confirmation. Cancelling an in-progress selection before release produces no crop. No recognition yet — this ticket is demoable purely as "the crop shown is visibly the right region, at full source quality."

**Blocked by:** 01, 02

**Status:** ready-for-agent

- [ ] Reader gains a control to enter/exit selection mode without disrupting the existing scroll gesture or the tap-to-toggle-controls gesture
- [ ] Dragging in selection mode draws a visible rectangle tracking the gesture
- [ ] Releasing produces and displays the cropped source-pixel region (not a screenshot of the scaled on-screen rendering)
- [ ] Cancelling an in-progress selection before release discards it — no crop is produced
- [ ] Verified on at least one compact iPhone layout and one larger iPhone layout
