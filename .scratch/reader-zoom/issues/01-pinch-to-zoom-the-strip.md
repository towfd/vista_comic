# 01 — Pinch to zoom the strip, without breaking auto-advance

**What to build:** A reader who finds a title's lettering too small pinches, and the whole vertical strip enlarges. The magnification is a property of reading, not of a Page: it persists as they scroll from Page to Page, so it is set once rather than re-established on every Page. Pinching back in returns to the normal full-width view, and the scale stops there — full width is the bottom of the gesture, so "back to normal" needs no control to find. The upper bound is 3x. Both bounds rubber-band rather than stopping dead, so the reader feels a limit instead of a stuck gesture.

At 1.0 the Reader must be indistinguishable from today's.

Zoom is a change of **layout width**, not a rendering transform: the strip is laid out at the container width multiplied by the scale, inside a scroll view that scrolls both axes. Because Pages are laid out to fill the available width at their natural aspect ratio, a wider strip is proportionally taller, and everything the Reader already derives from its scroll view — resume positioning, scroll geometry, scroll phase, per-Page visibility tracking — keeps working natively. The existing reserved-height calculation is already parameterised by width and needs no change. A pure rendering transform was rejected because it does not participate in layout, so the scroll view would never learn the content had grown and no horizontal scrolling would exist; bridging to UIKit's scroll view was rejected because it would take the whole progress, prefetch and auto-advance machinery with it.

During the pinch the strip is transformed, anchored at the gesture's focal point, so it tracks the fingers; on release the final scale is committed as the real layout width and the Pages re-render crisply. This is not a performance refinement layered on top — focal-point anchoring is a natural property of a transform and would otherwise have to be reimplemented as scroll-offset arithmetic.

**The bottom-edge inferences must be defended, and that is why this ticket is large.** The Reader decides "the reader pulled past the end" from content offset, content height and container height. Zoom changes content height by up to 3x, and the dangerous direction is downward: pinching from 3x back to 1x collapses the content to a third of its height while the scroll offset is still the old, larger value — which satisfies the past-the-bottom test anywhere beyond the first third of a chapter. That is the same class of false trigger `.scratch/reader-auto-advance-false-trigger/` was opened for, except that with zoom it is reproducible on demand rather than requiring an iPad and a keyboard.

Both consumers of the inference — auto-advance, and the reachedEnd detection that marks a chapter read — are therefore inert whenever the scale is not 1.0, and **stay inert after the scale returns to 1.0 until a genuine one-finger scroll re-arms them**. The re-arm is deliberately a gesture condition rather than a timer or a delay: a scroll view clamping its offset after its content shrinks emits geometry updates but produces no new touch, so this closes the window structurally instead of racing it. This mirrors the discipline PR #65 established for every geometry-derived conclusion in this Reader, and the existing scroll-driven gate is kept, not replaced.

Splitting the interlock out into its own ticket was considered and rejected: shipping the zoom first would mean shipping a known reader-teleport regression, and shipping the interlock first would mean shipping logic whose new inputs cannot yet be produced.

An accepted consequence, not an oversight: a chapter read to its end entirely while magnified is not marked `read` and stays `reading`. Per-Page progress is unaffected, because it comes from Page visibility rather than from geometry, so the resume position is still correct.

The scale returns to 1.0 whenever the chapter changes and whenever the Reader is dismissed. Nothing is persisted anywhere — no per-comic memory, no user defaults, no store.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Pinching enlarges the whole strip, and the magnification persists while scrolling from Page to Page
- [ ] The scale is bounded to 1.0–3.0, and both bounds rubber-band and settle at the bound
- [ ] At 1.0 the Reader renders and behaves identically to before this ticket
- [ ] Zooming is centred on the pinch's focal point
- [ ] While magnified, dragging sideways reveals the rest of the Page
- [ ] The horizontal position is preserved while scrolling vertically
- [ ] The strip tracks the fingers during the pinch and renders crisply at the committed size once released
- [ ] Changing chapter returns the scale to 1.0; leaving the Reader returns it to 1.0; nothing is persisted
- [ ] Auto-advance does not fire while the scale is not 1.0
- [ ] Read-detection does not mark a chapter read while the scale is not 1.0
- [ ] After the scale returns to 1.0, both stay inert until a genuine one-finger scroll occurs — a pinch alone never re-arms them
- [ ] Pinching from 3x back to 1.0 mid-chapter changes neither the chapter nor the read state
- [ ] With no zoom having occurred, auto-advance and read-detection behave exactly as today, and their existing tests pass unchanged
- [ ] The arming decision is a standalone pure value type with its own unit tests, rather than booleans spread through the Reader view
- [ ] Per-Page progress reporting, prefetching, retention and preview (peek) mode are unaffected at every scale
- [ ] Tapping to show and hide the controls remains immediate, with no double-tap disambiguation delay introduced
- [ ] Rotating the device or resizing the window keeps the magnified strip coherent
- [ ] Unit tests cover clamping at both bounds, laid-out width as a function of container width and scale, the arm/disarm state machine including that a scroll phase occurring during a pinch does not re-arm, and that the 3x→1x collapse shape returns false while disarmed
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout
