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

**Status:** ready-for-agent

- [ ] Downloading beyond the cap succeeds rather than being refused, and ticket 01's temporary hard stop is gone
- [ ] Admitting a download at the cap removes exactly the chapter with the oldest started-at time
- [ ] Eviction removes both the page files and the chapter record, and the space is genuinely freed
- [ ] A slot is occupied from the moment a download starts, so queuing many at once cannot exceed the cap
- [ ] Admitting five chapters at the cap evicts exactly five
- [ ] The chapter currently open in the Reader is not evicted while it is open
- [ ] Read state is not consulted when choosing what to evict
- [ ] The number of downloads in use against the cap is visible to the reader
- [ ] An evicted chapter is no longer reported as available offline and its rows revert to a not-downloaded state
- [ ] Evicting a chapter does not disturb queued reading positions
- [ ] Eviction is tested directly against the store with an injected temporary directory, including the boundary cases at exactly the cap and one over
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering driving past the cap and confirming the oldest disappears
