# 03 — Offline reading progress catches up on reconnect

**What to build:** The reader finishes three chapters on a flight. They land, the connection comes back, and the app knows where they got to — 繼續閱讀 opens the right chapter at the right page, and the chapters they finished are marked accordingly.

Without this, ticket 02 ships a feature whose most visible behaviour looks like a bug. Progress writes are currently swallowed on failure, and that was the right decision when a failure meant a passing blip: a progress store that is down must never interrupt reading. Once reading offline is a normal thing to do, the same rule quietly discards an entire session, and the reader's evidence is that the app forgot several hours of reading.

**This ticket is sequenced immediately after 02 for a practical reason**: from the moment offline reading works, the loss is real and the repo owner will hit it during their own verification of 02.

This introduces `PendingProgressStore`, the feature's second seam. It is kept separate from `OfflineChapterStore` because the two have genuinely different lifetimes — downloaded content is removed when the cap evicts it, a queued position disappears only once the server has accepted it, and neither event should be able to disturb the other.

The queue is keyed by comic and chapter and holds only the most recent page for each, so a whole offline session collapses to one entry per chapter rather than a log of every page turn. It is bounded, and it persists across relaunch — a reader who closes the app on the plane has not thrown their session away. It is flushed after the next successful backend request, and entries are dropped only once the server has taken them.

The existing contract of the progress write is preserved exactly: it still never interrupts reading and never surfaces an error to the reader. It now enqueues where it previously discarded.

**This is a catch-up queue, not a sync engine.** The backend remains the source of truth for progress. There is no merge policy, no conflict resolution, and no local-first progress store — those were considered and deliberately left out, because they turn a small honest fix into an independent architecture project.

**Blocked by:** 02 — Read a downloaded chapter with no network.

**Status:** implemented on branch `feat/offline-progress-queue`, 2026-08-18 — unit-verified, awaiting the repo owner's fly-and-land device pass.

- [x] A progress write that cannot reach the backend is queued instead of discarded
- [x] A second write for the same chapter replaces the first rather than appending
- [x] The queue survives closing and relaunching the app
- [x] The queue is flushed after the next successful backend request, and entries are dropped only on success
- [x] After reconnecting, the reading position and read state reflect what was read offline
- [x] After reconnecting, 繼續閱讀 opens the chapter and page the reader actually reached
- [x] Reading is never interrupted and no error is surfaced when a write cannot be sent
- [x] The queue is bounded and cannot grow without limit
- [x] Preview (peek) mode still never writes or queues progress
- [x] Eviction of a downloaded chapter does not remove that chapter's queued position, and flushing a position does not affect downloaded content
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering reading several chapters offline and then reconnecting

## What was built

- `Networking/PendingProgressStore.swift` — `PendingProgress`, the seam, a file-backed store under Application Support (persisted, so closing the app on the plane is not throwing the session away) and an in-memory double.
- `PendingProgressFlusher` — an actor beside the decorator. One flush at a time, oldest entry first, each dropped **only** once the server has taken it.
- `OfflineFallbackComicRepository.saveProgress` queues what it could not send. The write's contract is otherwise untouched: it never interrupts reading and surfaces nothing to the reader.
- The offline `readerChapter` fallback now answers `lastReadPage` from the queue, which closes the `nil` ticket 02 left behind: a chapter reopened offline resumes where the reader actually got to.
- The Reader is **not** modified. Every progress write already funnelled through one gate, and that gate still decides everything about peek mode.

**The flush runs *before* the three reads, not after them.** The library, the comic detail and the reader request are the three places reading progress is displayed — 繼續閱讀, the read badges, the resume position — so catching the server up first is the difference between landing and seeing where you got to, and landing, seeing yesterday, and having to refresh again. It costs nothing when the queue is empty, and when the reader is still offline it costs one request that fails the way every other request is already failing.

**Two decisions worth naming.** A write the server *refuses* (a 4xx — a chapter that no longer exists) is dropped rather than retried forever: leaving it at the head of the queue would hold every later position behind it. And a 500 is not queued at all — the backend was reached, and queueing would be claiming otherwise; the reader never sees that error either way, since the write has always been best-effort.

## Verification

`BUILD SUCCEEDED`, whole `vista_comicTests` target passes, including 10 new tests in `PendingProgressTests`: last-write-wins per chapter, the bound dropping the oldest, survival across a relaunch, an unreachable write being queued with no error surfaced, a 500 not being queued, the queue being delivered on the next successful request, entries surviving a flush that could not connect, a refused entry being dropped rather than wedging the queue, an offline chapter resuming from the queue, and eviction leaving a queued position alone.

**Also fixed here:** ticket 01's `backgroundingPausesAndReturningResumesWithoutRefetching` was intermittently failing under parallel load. It counted requests across both halves of the test, which made it depend on exactly which fetches the pause interrupted — a page requested and then cancelled mid-flight is legitimately requested twice. It now asserts on the resumed half alone, which is the only half it has a claim about: nothing already on disk is re-fetched.

## Device checklist for the repo owner

The fly-and-land round trip, on one compact phone and one larger phone:

1. Online, download three chapters. Note where 繼續閱讀 currently points.
2. Airplane mode. Read all three: finish two, and stop deliberately in the middle of the third.
3. Force-quit the app while still in airplane mode, relaunch, and reopen the third chapter — it resumes where you stopped, not at the top.
4. Turn airplane mode off and open 書庫. Without pulling to refresh: 繼續閱讀 points at the third chapter, and the two finished ones are marked 已讀.
5. Open the third chapter again — it opens at the page you actually reached.
6. Jump to a page from 歷史紀錄 (peek mode) and leave: reading progress is unchanged, as before.
7. Read a chapter online, kill the backend mid-chapter, keep reading, bring it back: the position catches up with no error shown at any point.
