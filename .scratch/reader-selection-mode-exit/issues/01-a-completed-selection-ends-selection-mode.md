# 01 — A completed selection ends selection mode

**What to build:** Selecting text is one action, not a mode the reader has to remember to leave. Drawing a selection hands the crop to the result sheet and turns selection mode off; closing the sheet leaves the reader able to scroll immediately, with no second trip to the toolbar. Wanting another selection means tapping the button again.

Reported by the repo owner, 2026-08-10: "我發現我不會一直去截要辨識的圖片" — selections are occasional and deliberate, so a mode that persists until manually dismissed is wrong for how the reader is actually used. Today, closing the sheet leaves the reader still in selection mode with scrolling disabled, which reads as the reader having frozen.

Selection mode ends when a crop is actually **produced**, not when the sheet is dismissed. Same result for the reader, and a simpler rule: one successful selection ends the mode. It also means the reader visible behind an iPad form sheet goes back to normal immediately rather than sitting frozen under it.

The two ways a drag ends without producing anything — releasing inside the cancel zone, and a selection that did not overlap the displayed image — must **stay** in selection mode. Nothing was selected, so there is nothing to have finished, and dropping the mode there would punish a misdrag with a trip back to the toolbar.

**Status:** implemented and accepted by the repo owner, 2026-08-10 ([#65](https://github.com/towfd/vista_comic/pull/65))

View state with no seam a unit test can reach without rendering the reader; it is one assignment in the reader's `onCrop`, handed to device verification per CLAUDE.md.

Accepted on the owner's say-so rather than on a reported box-by-box sweep. The two worth a deliberate pass if anything here ever looks wrong are the last two: re-entering the mode, and a cancel-zone release *staying* in it. They are the only behaviours this change could have broken rather than improved, and neither is covered by a test.

- [ ] Drawing a selection opens the result sheet and leaves selection mode
- [ ] Dismissing the sheet leaves the reader scrollable with no further tap
- [ ] The toolbar button returns to its "enter selection" appearance
- [ ] Tapping it again re-enters selection mode as before
- [ ] Releasing inside the cancel zone stays in selection mode
- [ ] A drag that selects nothing on the page stays in selection mode
- [ ] On iPad, the reader behind the form sheet is scrollable rather than frozen
