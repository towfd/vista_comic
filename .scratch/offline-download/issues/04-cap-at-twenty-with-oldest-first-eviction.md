# 04 — Cap downloads at 20 chapters, evicting the oldest first

**What to build:** The reader downloads whatever they want and is never stopped to tidy up. Once twenty chapters are on the device, downloading a twenty-first removes the one that was downloaded longest ago and proceeds. The reader can see how much of the allowance is in use.

This replaces ticket 01's temporary refuse-at-twenty stop, which existed only so the device could not be filled while this ticket was still outstanding.

**This is the only irreversible, destructive logic in the feature, which is why it is its own ticket.** Its tests are the substance of the work, not an accompaniment to it.

The rules are deliberately simple, and the simplicity was chosen over a cleverer policy:

- **A download occupies its slot from the moment it starts**, not when it finishes. Without this, queuing many downloads at once would sail past the cap while every one of them was still in flight.
- **The oldest by started-at is removed** — record and page files together. Strict first-in-first-out. Read state is not consulted, and a read-aware policy (evicting finished chapters first) was considered and rejected in favour of a rule the reader can predict without knowing what the app thinks they have read.
- **Eviction is applied per chapter admitted**, so admitting five chapters at the cap evicts exactly five. The batch download interface that makes this reachable is ticket 06; the semantics belong here, with the eviction logic, and must be tested here rather than discovered there.
- **The chapter currently open in the Reader is never evicted** while it is open, whatever its age. Deleting the pages out from under someone who is reading them is never the right answer.

**An accepted failure mode, recorded so it is not later mistaken for a defect.** A chapter saved for a journey can be evicted by later downloads before it is read, and the reader will discover this at the moment they have no connection to recover it. This was raised during planning and knowingly accepted in exchange for downloading never becoming a chore. The 已下載 list (ticket 05) is what makes the queue visible, so the eviction can at least be seen coming.

The cap is a single constant. There is no settings screen, and none is added.

**Blocked by:** 01 — Download a chapter to the device.

**Status:** implemented on branch `feat/download-eviction`, 2026-08-18 — unit-verified, awaiting the repo owner's drive-past-the-cap device pass.

- [x] Downloading beyond the cap succeeds rather than being refused, and ticket 01's temporary hard stop is gone
- [x] Admitting a download at the cap removes exactly the chapter with the oldest started-at time
- [x] Eviction removes both the page files and the chapter record, and the space is genuinely freed
- [x] A slot is occupied from the moment a download starts, so queuing many at once cannot exceed the cap
- [x] Admitting five chapters at the cap evicts exactly five
- [x] The chapter currently open in the Reader is not evicted while it is open
- [x] Read state is not consulted when choosing what to evict
- [x] The number of downloads in use against the cap is visible to the reader
- [x] An evicted chapter is no longer reported as available offline and its rows revert to a not-downloaded state
- [x] Evicting a chapter does not disturb queued reading positions
- [x] Eviction is tested directly against the store with an injected temporary directory, including the boundary cases at exactly the cap and one over
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering driving past the cap and confirming the oldest disappears

## What was built

`admit` stops refusing and starts making room. It now takes the chapter the Reader is holding open, returns whatever it evicted, and is the single place both eviction and explicit deletion go through — the two are the same act and must not drift apart.

- **The oldest by `startedAt`, and nothing else consulted.** Not read state, not size, not how recently it was opened. The rule is one the reader can predict without knowing what the app thinks they have read.
- **Per chapter admitted**, so five in means five out. Ticket 06's batch download relies on that, and it is settled here rather than discovered there.
- **The chapter open in the Reader is never the victim.** The engine is told what is being read because the Reader is the only thing that knows; without it, the chapter someone is in the middle of is exactly what a full device would take.
- **Only when the device is full and everything on it is protected** does anything refuse — impossible at a cap of twenty with one chapter open, kept as an honest error for a store configured small.

The chapter list shows 已下載 n/20, which is the only place the limit is stated at all until 已下載 arrives in ticket 05 — the cap is never announced by refusing any more. Ticket 01's alert and its two strings are gone.

## Verification

`BUILD SUCCEEDED`; the whole `vista_comicTests` target passes. The eviction tests are the substance of this ticket and are against the real file-backed store in a temporary directory: filling exactly to the cap evicts nothing, one more evicts the oldest, the pages go with the record, five admissions at the cap evict exactly five, a finished chapter is evicted ahead of a newer unfinished one (read state is not a factor), the chapter being read is passed over for the next-oldest, and a device where everything is protected refuses rather than deleting something it was told not to.

At the engine level: downloading past the cap proceeds and the evicted chapter's row reverts to not-downloaded; the chapter announced as open survives while the next-oldest goes; a slot is counted from the moment a download starts, and cancelling gives it back.

**Queued reading positions are untouched by eviction** — structurally, since the two stores share nothing and eviction only removes its own chapter directory. The assertion for it lives in ticket 03's suite (`evictingADownloadedChapterLeavesItsQueuedPositionAlone`, PR #71), because that is where the queue exists; this branch is cut from `main` and does not carry it.

**Note on a flaky test:** this branch does not include #71's hardening of `backgroundingPausesAndReturningResumesWithoutRefetching`, so that test can still fail here under parallel load. The two changes are in different parts of the file and merge cleanly in either order. The unrelated pre-existing flake in `PageImageCacheTests` is unchanged and still not chased.

## Device checklist for the repo owner

1. Note which chapter is the oldest download, then download past twenty. The oldest disappears from the list's downloaded markers, and the new download proceeds without asking anything.
2. The 已下載 n/20 count on the chapter list is right before, during and after — and never goes above 20.
3. Queue several downloads at once at the cap: exactly as many chapters disappear as are added.
4. Open a downloaded chapter, and **while it is on screen** download past the cap from another device path if you can — or simply confirm the chapter you were reading is still readable offline afterwards. It must never be the one that went.
5. An evicted chapter's row goes back to offering a download, and opening it offline says 尚未下載 rather than failing oddly.
6. Compact and larger phone.
