# 08 — A chapter finished offline says so, offline

**What to build:** The reader finishes a chapter in airplane mode, goes back to the chapter list, and it is marked 已讀 — not 未讀, which is what it says today.

Reported by the repo owner from the device pass on ticket 03: *"在飛航模式下 這兩話閱讀完畢的不會變成閱讀完成的狀況"*. Everything else in that pass was correct, including the resume position offline, and everything was correct again once reconnected.

**The cause is the seam between the two halves of offline support, not a fault in either.** A chapter list's `readState` comes from `GET /comics/{id}`, which offline is replayed from the response stored the last time the app was online — a faithful record of a moment that is now out of date. The unsent progress queue knows better, but it is only consulted for the reader endpoint's resume position, so nothing brings the two together.

Neither ticket promised this. Ticket 02's criterion is that the library renders *from the last successful responses*, which is stale by construction; ticket 03's is that the position and read state are right **after reconnecting**, which they are. This is the gap between those two sentences.

**The fix is to state the stored answer in terms of what the queue knows**, at the one place a stored answer is produced. Only on the replay path: a live response is fresher than anything local, and the queue is flushed in front of it anyway.

**The rule is mirrored, not invented.** The backend derives read state in three lines (`backend/app/progress_store.py`): no progress is `unread`, a last page at or past the page count is `read`, anything else is `reading`. It is pinned by backend tests, so mirroring it costs one function and cannot drift quietly. Getting it wrong in either direction is visible — a chapter that says 已讀 offline and 閱讀中 on reconnect is worse than one that was simply stale.

**The library card is deliberately left alone.** 繼續閱讀 and 上次閱讀 are decided by a rule with real branching — the most recent reading chapter, else the first unread, else the first — and reproducing that on the client is duplication rather than a mirror. The repo owner verified both are correct on reconnect, which is where they matter.

**Blocked by:** 03 — Offline reading progress catches up on reconnect.

**Status:** implemented on branch `feat/offline-read-state`, 2026-08-18 — unit-verified, awaiting the repo owner's airplane-mode check.

- [x] A chapter read to the end offline shows as 已讀 in the chapter list while still offline
- [x] A chapter stopped partway shows as 閱讀中
- [x] A chapter with nothing queued keeps exactly what the stored response said
- [x] A live response is never overlaid — only a replayed one
- [x] The read state shown offline agrees with what the backend derives, so reconnecting changes nothing on screen
- [x] The library card's 繼續閱讀 and 上次閱讀 are unchanged
- [x] No XCUITest is written; the device check is finishing a chapter in airplane mode and going back to the list

## What was built

One function in `OfflineFallbackComicRepository`, on the replay path only: a stored chapter list is re-stated in terms of the positions the queue is still holding. A chapter with a queued position gets its read state derived and its `lastReadPage` filled in; a chapter with nothing queued is returned exactly as stored.

`readState(lastPage:pageCount:)` mirrors `progress_store.read_state` — at or past the page count is `read`, otherwise `reading` — and is tested against the same boundaries the backend's own tests pin (`backend/tests/test_progress.py`). The mirror is the point: if this said `read` where the backend says `reading`, reconnecting would change the badge under the reader, which looks like the app changing its mind and is worse than the stale badge it replaces.

Nothing is invented. The library card's `lastReadAt` and `continueChapterId` are passed through untouched.

## Verification

`BUILD SUCCEEDED`; whole `vista_comicTests` target passes, including 5 new tests in `PendingProgressTests`: a chapter finished offline reports `read` while still offline, one stopped partway reports `reading` with its page, one with nothing queued is untouched, a live response is never overlaid (and its queue is flushed in front of it), and the rule agrees with the backend's boundaries.

## Device check for the repo owner

Airplane mode, finish a chapter, go back to the chapter list: it says 已讀 rather than 未讀. Reconnect and pull to refresh: it still says 已讀 — nothing changes under you. Compact and larger phone.
