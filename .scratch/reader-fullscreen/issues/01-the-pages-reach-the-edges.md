Status: done — device-verified by the repo owner, 2026-09-01

# 01 — The pages reach the edges

**What to build:** The reader's pages fill the screen, and the selection cancel badge still
clears the control bar afterwards.

## The change

- The pages `ScrollView` ignores the safe area, so the strip is laid out edge to edge and
  scrolls under the status-bar and home-indicator regions.
- **Only the pages.** `controlsOverlay` is a sibling in the same `ZStack` and keeps its
  insets, so the back button never sits under the Dynamic Island. Both bars already extend
  their material to the edges on their own.

## The measurement that comes with it

`controlBarHeight` means "how much of the reader this bar covers", and that is now the bar
plus the top inset it sits under. Measure it including that extension rather than adding an
inset arithmetic elsewhere — the value keeps its documented meaning, and
`selectionCancelZoneFrame` needs no new parameter.

The failure this prevents is specific: a badge drawn at the old offset is underneath the
control bar. It is placed correctly, it is impossible to see, and there is nothing on
screen to explain why the drag cannot be cancelled.

## What must not change

- Zoom, pan, and the end-of-chapter shift. They read the container from scroll geometry, so
  a taller container is followed rather than assumed — but the reader must not jump, rescale,
  or lose its position when this lands.
- Auto-advance. The pull-past-the-end threshold is measured off the same geometry.
- Where the reader resumes to, and what page progress reports.
- Selection and crop mapping, which work in the page's own display frame.

## Acceptance criteria

- [x] With the controls hidden, a page runs to the top and bottom edges of the screen with no
      band above or below it
- [x] The controls, when tapped up, are still fully inside the safe area — the back button is
      not under the Dynamic Island and the chapter bar is not under the home indicator
- [x] Both bars' material still reaches the screen edges
- [x] In selection mode the cancel badge is fully visible, below the control bar, on a device
      with a top inset
- [x] Pinch, pan, and the end-of-chapter shift behave as before
- [x] Pulling past the end still advances the chapter, and an ordinary scroll to the bottom
      still does not
- [x] Reopening a chapter resumes to the same page as before this change
- [x] The loading, failed, and offline-unavailable states are unaffected
- [x] No XCUITest is written, built, or run — the device checklist is the deliverable

## File boundary

- `vista_comic/vista_comic/Features/ComicPage/ComicView.swift`
- `vista_comic/vista_comicTests/` if a pure function ends up changing

Every criterion on this ticket is visual, and all of them are answered by the repo owner's
device pass on 2026-09-01, which passed with no changes asked for. The unit suite only ever
said that nothing else broke.

**The measurement held.** The risk named below — a background that does not expand into the
inset, leaving the cancel badge under the control bar — did not happen on a real device.

## What was built

Two changes in `ComicView.swift`, and no new files.

1. **`.ignoresSafeArea()` on the pages `ScrollView`**, applied there rather than on the
   enclosing `ZStack` — which is what keeps `controlsOverlay` inside the insets.
2. **`topObstruction` replaces `controlBarHeight`**, measured through a background layer that
   ignores the top inset:

   ```swift
   .background(alignment: .top) {
       Color.clear
           .ignoresSafeArea(edges: .top)
           .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topObstruction = $0 }
   }
   ```

   The same mechanism the bar's own material already uses, so one measurement gives the whole
   obstruction and `selectionCancelZoneFrame` needs no arithmetic at the call site. The rename
   is the point of the change rather than tidying: the value is no longer the height of a bar,
   it is how much of the reader something covers, and only the second reading stays true.

**The risk to look for on device** is that measurement. If the background does not expand into
the inset, `topObstruction` silently keeps today's value and the cancel badge sits under the
control bar — placed correctly, invisible, with nothing on screen to explain why. It fails
towards current behaviour rather than towards something new, which is why it is written this way,
but it is checked first below.

## Verification

`xcodebuild test -only-testing:vista_comicTests` on iPhone 16 (18.1): **TEST SUCCEEDED**, 572
test cases passed, 0 failed. `SelectionCancelZoneTests` already exercised the free function
under its own name, so the rename needed no test changes.

Not verified here, by rule: everything this ticket is actually about. No XCUITest was written,
built, or run.

## Device checklist for the repo owner

1. **Open a chapter and hide the controls.** The page runs to the very top and bottom of the
   screen — no band above, none below. This is the whole ticket.
2. **Selection mode, first.** Tap the select-text button, start a drag: the round cancel badge
   at the top-right must be **fully visible, below the control bar**. If it is clipped by the
   bar or missing, the measurement did not expand and I need to know.
3. Drag into the badge and lift — the selection still cancels.
4. Draw a real selection: the crop is still the region you drew, not shifted up or down.
5. **Tap the controls up.** The back button is clear of the Dynamic Island, the chapter bar is
   clear of the home indicator, and both bars' material still reaches the screen edges.
6. **Pinch and pan.** Zoom in, move around, release. Nothing jumps and nothing rescales when you
   let go, and the reader stays where it was.
7. **Scroll to the bottom of a chapter and stop.** It does not advance. Then keep pulling past
   the end — it advances, and the next chapter starts at page one.
8. **Leave and reopen the chapter.** It resumes where you were, same as before.
9. **A comic you have downloaded, in airplane mode**, and a chapter you have not — the failure
   and offline-unavailable screens are unchanged and still inside the safe area.
10. **Both phone sizes**, and rotate one of them if you ever read that way.
