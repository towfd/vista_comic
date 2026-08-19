# 04 — Collecting works with no network

**What to build:** The reader collects words on a train with no signal. Nothing is lost, nothing warns them, and the words arrive on the server the next time the app has a connection.

**This is why the ticket exists at all:** offline download shipped, so reading offline is now normal — and reading offline is exactly when the most words get looked up. A collection step that needs a connection would miss the reader's densest collecting session, and the deck is the one thing in this PRD that cannot be caught up later by working harder.

Mirror `PendingProgressStore` and `PendingProgressFlusher` closely: a protocol with a file-backed store and an in-memory double, and an actor that flushes oldest first, removes an entry **only** once the server has taken it, drops a 4xx so one bad entry cannot wedge the queue, and stops on anything else. Flush opportunistically whenever a card call succeeds — the trick `OfflineFallbackComicRepository` uses, where a success is the proof that the network is back.

**This is a catch-up queue, not a sync engine**, on the same terms as the progress queue: the backend stays the source of truth, and there is no merge policy.

A queued card counts as collected for ticket 03's local marker. Duplicate protection is local as well as remote — enqueueing deduplicates on the normalised key, so tapping add twice offline queues one card, and ticket 01's idempotent `POST` catches whatever slips past.

**Blocked by:** 02.

**Status:** implemented on branch `feat/deck-lookup-marker`, 2026-08-19 — `BUILD SUCCEEDED`, `TEST SUCCEEDED` across the whole `vista_comicTests` target. **Awaiting the repo owner's device pass** (checklist below).

- [x] An add that cannot reach the backend is queued rather than lost, and the button still shows collected
- [x] Enqueueing the same normalised key twice queues one entry
- [x] The queue survives closing and relaunching the app
- [x] The queue is bounded and cannot grow without limit
- [x] Flushing sends oldest first and removes each entry only once the server has taken it
- [x] A 4xx entry is dropped rather than retried forever; any other failure stops the flush and leaves the queue intact
- [x] Two flushes cannot run at once
- [x] After reconnecting, each word collected offline exists on the server exactly once
- [x] Collecting offline never surfaces a blocking error
- [x] The queue and the deck snapshot are independent: clearing or refreshing one does not disturb the other
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering an airplane-mode collect and reconnect

## What was built

- `Networking/PendingCardStore.swift` — `PendingCard`, `CardIdentity`, the protocol, a file-backed store and an in-memory double, bounded at 200 entries.
- `Networking/OfflineFallbackStudyRepository.swift` — the decorator and `PendingCardFlusher`, mirroring `OfflineFallbackComicRepository` and `PendingProgressFlusher`.
- `StudyRepository.collect` now returns `CollectOutcome`; the environment default is the decorator wrapping `APIStudyRepository`.
- `SelectionActions` — a `.queued` outcome and `isQueued(_:targetLanguage:in:)`.

**Five decisions worth review:**

1. **`.queued` is not a lesser success.** The button says exactly what it says for `.collected`. The reader's choice was recorded and will be delivered; saying anything else asks them to carry a connection problem that is not theirs.
2. **First write wins, unlike `PendingProgressStore`'s last write wins.** A reading position improves as the reader advances; a collected line does not change, and the earlier `queuedAt` is the one that reflects when they actually chose it.
3. **A 4xx is thrown, not queued.** It is not a connection problem, and queueing it would only mean offering the server the same rejected thing until the flush's own 4xx rule discarded it.
4. **`cards()` flushes before it reads.** That response becomes the deck snapshot the marker reads, and a snapshot taken before the queue drained would be missing exactly the words collected most recently.
5. **A queued line never pretends to be a `LearningCard`.** It has no server id, so `queuedLines()` is separate from `knownCards()`. Synthesising an id would put a number in the data model no backend ever issued, and every later stage would have to know which ids were real.

`PendingCard.identity` is computed rather than stored, so a line can never be persisted under one version of the normalisation rule and compared under another.

## Verification

**`BUILD SUCCEEDED`**, and **`TEST SUCCEEDED` across the whole `vista_comicTests` target** with this ticket's code and tests in place — 19 new tests in `PendingCardTests.swift`, covering: dedupe on identity, another language being a separate entry, first-write-wins, oldest-first ordering, the bound dropping the oldest, survival across a rebuild over the same directory, queueing on a connection failure, offline collect never throwing, a 4xx being reported rather than queued, a queued line being recognised while **not** appearing as a card, a successful collect flushing the queue, `cards()` flushing first, and the flusher's send order, success-only removal, 4xx drop, connection-failure stop, and empty no-op.

**A second, targeted run to list those tests individually was stopped before producing output, and was not retried** — `CLAUDE.md` §5 says a killed run is what breaks the test host, and that the rule is to hand back rather than look for a way through. It was redundant in any case: the files are members of the target that just passed.

No XCUITest was written, built, or run.

## This supersedes one item from ticket 02

Ticket 02's checklist item 7 said that with the backend stopped, the button reports it could not add. **That is no longer the behaviour** and should not be re-tested from that list: a collect that cannot reach the backend now queues silently and shows as collected. Only a 4xx still surfaces a failure.

## Device checklist for the repo owner

1. **Airplane mode. Collect two words you have never collected before.** Both show as added, with no error and no delay worth noticing.
2. Still offline, **re-select one of them**. It is recognised as collected — the queue counts for the marker, not just the deck.
3. **Force-quit the app while still offline, relaunch, and re-select one of those words.** Still recognised. This is the whole point of the queue persisting.
4. **Turn the connection back on and open the app.** Without doing anything else, the queued words reach the server: `GET /cards` holds each of them **exactly once**.
5. **Collect the same word twice while offline** (add, dismiss, re-select, add again). After reconnecting there is still one card.
6. Offline, collect a word, then reconnect and collect a *different* word. Both arrive — the second collect is what triggers the flush of the first.
7. **Refusal still shows an error**: with the connection up, try a selection longer than 200 characters. It reports a failure rather than queueing silently.
8. Downloading and evicting chapters does not disturb queued words, and vice versa — the two queues are independent stores.
