# 05 — 已下載: review what is on the device, and delete it

**What to build:** One place that answers "what can I read without a connection, and what is it costing me" — and lets the reader act on the answer. Downloaded chapters are listed grouped by comic, each showing its size and state, with the allowance in use shown at the top. A chapter can be deleted individually, and everything can be cleared at once.

It is also the **offline entry point**. Opening a chapter from here goes straight into the Reader, so a reader on a plane has a screen that is guaranteed to be about things that work, rather than browsing 書庫 and finding out one chapter at a time.

Deletion is what makes ticket 04's eviction tolerable. Until this exists, the reader's only influence over what is on the device is the order in which they downloaded things; after it, first-in-first-out is a default they can override — they can free the slot they want freed instead of the one the clock chose.

Deleting everything is irreversible and asks for confirmation first, following the destructive-action pattern this app already uses for removing a saved record. Deleting one chapter is a smaller loss and needs no dialog: it removes the chapter's files and record and frees its slot immediately.

**Blocked by:** 01 — Download a chapter to the device; 04 — Cap downloads at 20 chapters, evicting the oldest first.

**Status:** implemented on branch `feat/downloads-screen`, 2026-08-18 — unit-verified, awaiting the repo owner's device pass.

- [x] A 已下載 surface lists every downloaded chapter, grouped by comic
- [x] Each entry shows the chapter's identity, its size, and whether it is complete or still downloading
- [x] The number of downloads in use against the cap is shown
- [x] A chapter can be deleted from the list, removing its files and record and freeing its slot immediately
- [x] Everything can be cleared in one action, behind a confirmation, since it is irreversible
- [x] Opening an entry goes directly into the Reader at that chapter
- [x] The screen works with no connection, since that is when it matters most
- [x] The list stays correct after an eviction, so a chapter removed by the cap disappears from it
- [x] An empty state explains that nothing has been downloaded yet
- [x] Deleting a chapter does not disturb queued reading positions
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout

## What was built

**已下載 is a tab, not a screen pushed from somewhere.** It is the offline entry point, so it has to be reachable at the moment 書庫 may be the least useful thing on the device. It sits between 書庫 and 歷史紀錄.

- `Features/Downloads/DownloadedComicGroups.swift` — the arrangement as a free function over two arguments, so the ordering can be tested without rendering anything. Comics come newest-download first, chapters within a comic in reading order: the two orders answer different questions and deliberately differ.
- `Features/Downloads/DownloadsView.swift` — the list, the allowance (slots and bytes), swipe-to-delete, delete-all behind a confirmation, the empty state, and the Reader as a navigation destination in this tab's own stack.
- `components/DownloadedChapterRow.swift` — identity, size, and a progress line only while a chapter is still arriving.
- `OfflineChapterStore.sizeOnDisk(of:)` — measured from the page files rather than remembered, since a record is written before the first page arrives and a partly downloaded chapter's size changes as it fills. It measures the pages only: the record beside them is a few hundred bytes of bookkeeping the reader did not ask about.
- `ChapterDownloadManager.delete(_:)` / `deleteEverything()`.

**Nothing here touches the network.** The chapter records carry their own comic and chapter titles precisely so this screen needs no catalog — a list that could only name things by id would be no use in the one situation it exists for.

**Deleting one chapter asks nothing; deleting everything asks first.** One chapter is a small, re-downloadable loss, and a dialog per row would make tidying up the chore this feature exists to avoid. Clearing the device is irreversible with no undo, so it follows the confirmation pattern the app already uses for removing a saved record.

**A chapter still downloading is not tappable.** It would open, and offline it would fail — which is the one thing this screen exists to stop happening. Deleting one instead cancels it, discarding the partial chapter by the path that already knows how to stop the work first.

**Sizes are measured off the main thread.** Twenty chapters is a couple of thousand files, and the measuring happens while the reader is looking at the screen.

The list is reloaded from two observable signals the manager already mirrors: the slot count, which moves on every admission, eviction, cancellation and deletion, and the completed set, which moves when a download finishes. That is what keeps an evicted chapter from lingering here.

## Verification

`BUILD SUCCEEDED`; the whole `vista_comicTests` target passes apart from the pre-existing `PageImageCacheTests` flake noted below.

New: 6 tests for the arrangement (grouping, both orders, sizes and their per-comic total, an unmeasurable chapter counting as nothing rather than breaking the screen, a renamed comic showing its current name, and nothing downloaded being no groups); 3 for deletion at the engine level (a completed chapter freeing its slot and reverting its row, an in-flight download being stopped and discarded rather than deleted underneath itself, and clearing the device leaving no files behind); and one for `sizeOnDisk`.

**Queued reading positions are untouched by deletion**, structurally — the two stores share nothing — and the assertion for it already exists in `PendingProgressTests.evictingADownloadedChapterLeavesItsQueuedPositionAlone`, which deletes explicitly.

**The pre-existing flake is still unchased:** `PageImageCacheTests/anExplicitRequestReRequestsAPageThePrefetchWindowGaveUpOn` failed on roughly four of fifteen full-suite runs today. It is unrelated to this work.

## Device checklist for the repo owner

1. With a few chapters downloaded, open 已下載: they are grouped by comic, each with its size, and the header shows n/20 and the total.
2. Tap a downloaded chapter — the Reader opens on it directly.
3. In airplane mode, the whole screen still works and reading from it still works.
4. Swipe a chapter away: it disappears immediately, the count drops, and the row back in the chapter list offers a download again.
5. Delete all: the confirmation appears, and afterwards the screen shows its empty state and the count is 0/20.
6. Start a download and open 已下載 while it runs: it appears with its progress, is not tappable, and swiping it away stops the download.
7. Drive past the cap and confirm the evicted chapter disappears from this list without needing a refresh.
8. Compact and larger phone.
