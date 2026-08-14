# 03 — Offline reading progress catches up on reconnect

**What to build:** The reader finishes three chapters on a flight. They land, the connection comes back, and the app knows where they got to — 繼續閱讀 opens the right chapter at the right page, and the chapters they finished are marked accordingly.

Without this, ticket 02 ships a feature whose most visible behaviour looks like a bug. Progress writes are currently swallowed on failure, and that was the right decision when a failure meant a passing blip: a progress store that is down must never interrupt reading. Once reading offline is a normal thing to do, the same rule quietly discards an entire session, and the reader's evidence is that the app forgot several hours of reading.

**This ticket is sequenced immediately after 02 for a practical reason**: from the moment offline reading works, the loss is real and the repo owner will hit it during their own verification of 02.

This introduces `PendingProgressStore`, the feature's second seam. It is kept separate from `OfflineChapterStore` because the two have genuinely different lifetimes — downloaded content is removed when the cap evicts it, a queued position disappears only once the server has accepted it, and neither event should be able to disturb the other.

The queue is keyed by comic and chapter and holds only the most recent page for each, so a whole offline session collapses to one entry per chapter rather than a log of every page turn. It is bounded, and it persists across relaunch — a reader who closes the app on the plane has not thrown their session away. It is flushed after the next successful backend request, and entries are dropped only once the server has taken them.

The existing contract of the progress write is preserved exactly: it still never interrupts reading and never surfaces an error to the reader. It now enqueues where it previously discarded.

**This is a catch-up queue, not a sync engine.** The backend remains the source of truth for progress. There is no merge policy, no conflict resolution, and no local-first progress store — those were considered and deliberately left out, because they turn a small honest fix into an independent architecture project.

**Blocked by:** 02 — Read a downloaded chapter with no network.

**Status:** ready-for-agent

- [ ] A progress write that cannot reach the backend is queued instead of discarded
- [ ] A second write for the same chapter replaces the first rather than appending
- [ ] The queue survives closing and relaunching the app
- [ ] The queue is flushed after the next successful backend request, and entries are dropped only on success
- [ ] After reconnecting, the reading position and read state reflect what was read offline
- [ ] After reconnecting, 繼續閱讀 opens the chapter and page the reader actually reached
- [ ] Reading is never interrupted and no error is surfaced when a write cannot be sent
- [ ] The queue is bounded and cannot grow without limit
- [ ] Preview (peek) mode still never writes or queues progress
- [ ] Eviction of a downloaded chapter does not remove that chapter's queued position, and flushing a position does not affect downloaded content
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering reading several chapters offline and then reconnecting
