# 04 — Collecting works with no network

**What to build:** The reader collects words on a train with no signal. Nothing is lost, nothing warns them, and the words arrive on the server the next time the app has a connection.

**This is why the ticket exists at all:** offline download shipped, so reading offline is now normal — and reading offline is exactly when the most words get looked up. A collection step that needs a connection would miss the reader's densest collecting session, and the deck is the one thing in this PRD that cannot be caught up later by working harder.

Mirror `PendingProgressStore` and `PendingProgressFlusher` closely: a protocol with a file-backed store and an in-memory double, and an actor that flushes oldest first, removes an entry **only** once the server has taken it, drops a 4xx so one bad entry cannot wedge the queue, and stops on anything else. Flush opportunistically whenever a card call succeeds — the trick `OfflineFallbackComicRepository` uses, where a success is the proof that the network is back.

**This is a catch-up queue, not a sync engine**, on the same terms as the progress queue: the backend stays the source of truth, and there is no merge policy.

A queued card counts as collected for ticket 03's local marker. Duplicate protection is local as well as remote — enqueueing deduplicates on the normalised key, so tapping add twice offline queues one card, and ticket 01's idempotent `POST` catches whatever slips past.

**Blocked by:** 02.

**Status:** not started.

- [ ] An add that cannot reach the backend is queued rather than lost, and the button still shows collected
- [ ] Enqueueing the same normalised key twice queues one entry
- [ ] The queue survives closing and relaunching the app
- [ ] The queue is bounded and cannot grow without limit
- [ ] Flushing sends oldest first and removes each entry only once the server has taken it
- [ ] A 4xx entry is dropped rather than retried forever; any other failure stops the flush and leaves the queue intact
- [ ] Two flushes cannot run at once
- [ ] After reconnecting, each word collected offline exists on the server exactly once
- [ ] Collecting offline never surfaces a blocking error
- [ ] The queue and the deck snapshot are independent: clearing or refreshing one does not disturb the other
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering an airplane-mode collect and reconnect
