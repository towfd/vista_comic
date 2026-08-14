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

**Status:** implemented, awaiting device verification (commit `38095ea` + review fixes; branch `feat/reader-zoom`)

Build succeeds on iPhone 16 Pro Max and iPhone SE (3rd generation); 218 unit tests pass, none failing, including the seven pre-existing auto-advance gate tests unchanged.

**`/code-review` found four real defects, all fixed before this line was written.** Recorded because two of them were introduced by judgement calls that looked like improvements:

1. **Pages would have been laid out at 900pt on a 393pt phone.** A scroll view with a horizontal axis proposes an *unspecified* width to its content, and a page sized `maxWidth: .infinity` answers that with its ideal width — the source image's own. An earlier attempt to leave the width unimposed at full width (to dodge a speculative landscape safe-area concern) would have broken the ticket's most important criterion. The width is now imposed at every scale.
2. **The pinch was not anchored at the focal point** — it used the top of the viewport, and never read the gesture's own anchor.
3. **The strip snapped sideways on release**, because the commit corrected the vertical offset only.
4. **Rotating while magnified threw the reader through the chapter**, since a container resize rescales the strip exactly as a pinch does but had no matching offset correction.

**Two review findings were deliberately not acted on**, and belong to a later change rather than this one:

- `readerPassedBottom`'s `isScrollDriven:` parameter is now fed a broader arming decision than its name suggests, and wants renaming. Doing so would edit the existing auto-advance tests, which this ticket promises to leave untouched.
- The three geometry values those two call sites pass separately are a data clump that `ReaderScrollMetrics` half-solves. Bundling them changes a signature the same tests pin.

**Verify on device — this is the handoff, per `CLAUDE.md`'s verification rules.** In rough order of what would hurt most if wrong:

- Read a chapter normally without zooming at all, on both a compact and a large phone: page size, scrolling, tapping to show and hide the controls, and pulling past the bottom to advance must all feel exactly as before.
- Zoom to 3x in the middle of a chapter, then pinch back to full width. **The chapter must not change and must not be marked read.** Repeat deep into a long chapter, where the stale offset is largest.
- Pinch slowly and check the strip tracks the fingers, and that what was under them is still under them when you let go — both zooming in and zooming out.
- Pinch past both bounds and confirm it resists and settles at full width and at 3x.
- Zoom in, then scroll several pages: the magnification stays, the horizontal position stays, and pages keep loading at the right size.
- Rotate the device while at 3x, and on iPad resize the window: the strip should stay coherent and you should stay roughly where you were.
- Change chapter while magnified, and leave and re-enter the reader: both must come back at full width.
- Resume: reopen a chapter you were part-way through, jump to a page from 歷史紀錄, and auto-advance past the end of a chapter. All three go through the scroll position that this ticket replaced, so all three are worth a look.
- Selection still works at full width — magnified selection is ticket 02.

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
