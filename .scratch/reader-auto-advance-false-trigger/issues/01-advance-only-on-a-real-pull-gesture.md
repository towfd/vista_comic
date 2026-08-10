# 01 — Advance chapters only on a real pull gesture

**What to build:** Correcting recognized text no longer moves the reader. Tapping the text field in the result sheet, letting the keyboard raise and lower, and dismissing the sheet all leave the reader on the chapter and the page it was on — mid-chapter, on an iPad, exactly where the bug reproduces today.

Auto-advance stops being inferred from scroll geometry alone. The reader tracks the scroll view's phase and treats "pulled past the end" as `false` whenever the scroll view is not actually being driven by the reader's finger — so a `contentSize` that collapses under a stationary reader can no longer read as an overscroll. Gate the *transform*, not just the action: a latched `true` that never falls back would fire on the next unrelated geometry change instead.

The bottom-reached detection that marks a chapter read gets the same treatment, for the same reason and with a real consequence of its own — a collapse deep in a chapter currently reports the last page and marks the chapter read without the reader ever seeing it. Deceleration counts as driven by the reader here: releasing a fling that lands at the bottom must still mark the chapter read.

`goTo` sets `pagesState` to `.loading` itself instead of leaving it to the async `loadPages()`. Today the gap between the two produces one render pass holding the new chapter's `.id`, the previous chapter's URLs and a stale `topPage` — a scroll view positioned deep into placeholder-height content, which is what turns one false advance into a run to the last chapter. Closing the gap removes the cascade independently of the gate above; both are wanted, since the gate alone would leave a latent mixed-state render and the reset alone would still allow a single wrong jump.

A genuine pull past the bottom must still advance, still restart the incoming chapter at page 1, and still overwrite its saved progress. `isPeek` still writes nothing.

**Out of scope:** the reading position still shifts when the content collapses, on the last chapter and everywhere else. That is the collapse itself, and it belongs to `.scratch/reader-page-prefetch/issues/03` (reopened).

**Status:** implemented — the reported defect confirmed fixed on device 2026-08-10 ("不會跳到最後一集了"); the rest of the checklist still to sweep

Unit-testable parts are covered by `ReaderAutoAdvanceGateTests`; everything involving the keyboard, the form sheet and real Page heights is device verification, which is the repo owner's (CLAUDE.md).

The confirmation covers the first three boxes below. The ones still worth a deliberate pass are the two the gate could plausibly have broken rather than fixed: that a genuine pull past the bottom still advances, and that releasing a fling at the bottom still marks a chapter read.

- [ ] Tapping the text field mid-chapter on iPad leaves the reader on the same chapter
- [ ] The same tap near the top of a chapter still leaves the reader where it was
- [ ] Dismissing the sheet and lowering the keyboard causes no chapter change
- [ ] Pulling past the bottom of a chapter still advances to the next one
- [ ] The chapter opened by a pull starts at page 1 and overwrites its saved progress
- [ ] Pulling past the bottom of the last chapter still does nothing
- [ ] Reaching the real bottom by dragging still marks the chapter read
- [ ] Reaching the real bottom by releasing a fling still marks the chapter read
- [ ] A collapse mid-chapter no longer marks the chapter read
- [ ] Changing chapters by chevron or chapter list shows the loading state, never the outgoing chapter's pages under the incoming chapter's identity
- [ ] Explicit chapter jumps still resume at their saved position
- [ ] Peek mode still writes no progress on any of the above
