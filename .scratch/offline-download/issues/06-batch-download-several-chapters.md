# 06 — Download several chapters in one action

**What to build:** A reader following a serial wants the next few chapters before they leave, not one tap at a time. From the chapter list they enter a selection mode, tick the chapters they want, and download them together.

This is the difference between the feature being usable and being tedious at the size the library has actually reached — past 300 chapters, preparing for a journey by tapping individual rows is the kind of chore that stops a feature from being used at all.

The chapters queue and download one after another under the same rules as a single download: foreground only, page-level resume, four page fetches at once, and each chapter completing only when every page is present. Progress is legible per chapter rather than as one aggregate bar, so an interrupted batch shows exactly which chapters made it.

**The interaction with the cap is the risk worth naming.** A batch admitted at the cap evicts exactly as many chapters as it admits — five in means five out. That semantic belongs to ticket 04 and is tested there; what this ticket must not do is find a way around it, most obviously by admitting the whole batch at once as though it were a single unit. Selecting more chapters than the cap allows is the case to think through: the reader should not be able to issue a batch that would evict chapters it is itself about to add.

**Blocked by:** 01 — Download a chapter to the device; 04 — Cap downloads at 20 chapters, evicting the oldest first.

**Status:** implemented on branch `feat/batch-download`, 2026-08-18 — **not built and not tested**, see Verification. The repo owner chose to proceed after the simulator test host wedged.

- [x] The chapter list offers a selection mode in which several chapters can be ticked
- [x] Confirming downloads every selected chapter, queued under the same rules as a single download
- [x] Each chapter shows its own progress, and completes independently of the others
- [x] Leaving selection mode without confirming downloads nothing
- [x] Already-downloaded chapters cannot be selected for download again
- [x] A batch admitted at the cap evicts exactly as many chapters as it admits
- [x] A batch cannot evict chapters that the same batch is in the process of adding
- [x] A batch larger than the cap allows is handled sensibly rather than silently thrashing
- [x] An interrupted batch resumes without re-fetching what already arrived, and shows clearly which chapters completed
- [x] Entering and leaving selection mode does not disturb normal chapter-list navigation
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout

## What was built

- `ChapterDownloadManager.download(comic:chapters:)` — the whole of the batch. It **admits one chapter at a time**, because there is no batch admission path at all: five chapters take five slots and therefore evict exactly five. Admitting a batch as a unit would be the obvious way around ticket 04's semantics, so the way is simply not built.
- `ChapterListView` gains a selection mode through three defaulted parameters, so every existing caller is untouched. While selecting, the row picks instead of navigating and the whole row is the target — a list being ticked through quickly is one where a near miss must not open the Reader. A chapter already on the device is dimmed and cannot be ticked.
- `ChapterPageView` owns the mode: `Select` to enter, `Download (n)` to confirm, `Cancel` to leave. Leaving discards the selection, so nothing is downloaded.

**A selection larger than the cap is refused, not trimmed.** Below the cap the batch cannot eat itself at all — eviction takes the oldest download, and every chapter in the batch is newer than everything already on the device — so the arithmetic does the work and the guard only has to stop the one case where it breaks down. Trimming would answer a question the reader did not ask, and letting it run would thrash the disk to arrive at the last twenty of whatever was selected.

Nothing else was needed: chapters already queue one after another (four page fetches at once is the limit, and two chapters at once would be eight), each already has its own progress ring, and page-level resume is already how an interrupted download continues.

## Verification — parse-checked only

**This branch has not been built or tested.** While fixing the flaky prefetch tests, the simulator test host wedged: builds complete, `xcodebuild test` hangs before "Testing started" — two simulators, ten minutes each, zero tests. The repo owner chose to proceed rather than spend more time on the environment, so this is written to be read rather than proven.

What was done: every changed Swift file passes `swiftc -parse`, which catches syntax but does **no type checking**. Five tests are written and not run — a batch finishing all of its chapters, a batch larger than the cap being refused with no request issued, a batch at the cap evicting exactly as many as it adds and taking the oldest first, a full-cap batch never evicting its own members, and a batch skipping what is already downloaded.

**Before trusting any of this, build and run `vista_comicTests` (⌘U).**

## Device checklist for the repo owner

1. Tap 選取 on a chapter list: rows gain ticks and stop opening the Reader when tapped.
2. Tick several and confirm: they queue and fill one at a time, each with its own ring, and the count on the button matched what was ticked.
3. Enter selection, tick some, then Cancel: nothing downloads.
4. An already-downloaded chapter cannot be ticked.
5. Background the app mid-batch and return: it carries on, and only the unfinished chapters are still working.
6. At the cap, confirm a batch of five: exactly five older chapters disappear, and none of the five being added does.
7. Select more than twenty and confirm: the limit is explained and nothing is downloaded.
8. Leave selection mode and confirm normal navigation and the per-row download button behave as before.
9. Compact and larger phone.
