# 05 — Report how often a collected word is looked up again

**What to build:** Every time the reader selects a line they have already collected, that fact reaches the server.

Nothing displays this number in stage 1. It is collected now because it cannot be collected retroactively, and because it is the cleanest evidence this system will ever get that a word has been forgotten: the reader just proved it by looking it up again. Stage 2 shows it, stage 3 weights scheduling by it, stage 4 weights sentence generation by it. Starting the count later means those stages begin with a column of zeros.

**The negative is never inferred.** Not looking a word up again is not evidence of knowing it — the reader may simply not have reached that page. Only the positive is recorded.

**Do not touch `due_on`.** Rescheduling on a hit belongs to stage 3, where scheduling exists.

**One accepted imprecision**, recorded in `spec.md` and worth repeating in a code comment so it is not later mistaken for a defect: a report whose response is lost after the server commits will be retried and counted twice. Deduplicating it needs a per-event table, which is not worth paying for a counter that only feeds a weighting.

**Blocked by:** 03, 04.

**Status:** implemented on branch `feat/deck-lookup-marker`, 2026-08-19 — `TEST BUILD SUCCEEDED`, and `xcodebuild test` exited 0 with zero test-case failures across `vista_comicTests`. **Device-verified by the repo owner, 2026-08-20.** One card's `lookup_count` went 0 → 3 across three separate re-lookups: the queue does not collapse repeats, which is the property this ticket exists for. Had it deduplicated, three forgettings would have been recorded as one.

- [x] A hit reports once per selection — not once per keystroke, re-render, or re-translate of the same selection
- [x] The report is queued when offline and sent on reconnect, using the same flusher discipline as ticket 04
- [x] `lookup_count` and `last_looked_up_at` reflect the reports
- [x] `due_on` is left untouched
- [x] A report for a card the server does not have is dropped rather than retried forever
- [x] Not re-selecting a word changes nothing about it
- [x] The double-count case carries a comment pointing at the spec rather than being treated as a bug

## What was built

- `Networking/PendingLookupStore.swift` — `PendingLookup`, the protocol, a file-backed store and an in-memory double, bounded at 500.
- `OfflineFallbackStudyRepository.recordLookup(id:)` — reports, or keeps the report until the backend can be reached, plus `PendingLookupFlusher`.
- `CroppedSelectionPreview` — reports once per card when the already-collected check hits.

**Three decisions worth review:**

1. **This queue does not deduplicate, unlike the card queue.** Two taps on the card queue mean one word; two lookups mean the reader forgot the same word **twice**, and collapsing them erases the only signal this ticket exists to capture. So `PendingLookup` carries its own `UUID` and `remove` matches on that rather than on `cardID` — matching on the card would silently halve the count whenever a twin was in flight.
2. **One report per card per sheet.** The reader can tap Translate several times on one selection — another language, or the same one after an edit — and each re-runs the check. Only the first sighting is an event; the rest are the same forgetting counted repeatedly, which would weight the later stages by how often they tap rather than by how often they forget.
3. **Reporting can never reach the reader.** No spinner, no error, no failure path into the UI. They asked for a translation and they have it. A 4xx is dropped outright: the card is gone from the server, and retrying will not bring it back.

`cards()` drains the card queue **before** the lookup queue, because a lookup can only be recorded against a card the server already has.

## Verification

`TEST BUILD SUCCEEDED`, then one `test-without-building` run: **`xcodebuild` exited 0 with zero test-case failures**, and 55 tests across this stage's suites passed, 15 of them new here.

**The `** TEST SUCCEEDED **` banner is absent from the log**, and that is worth recording rather than glossing: Xcode failed to save its result bundle (`mkstemp: No such file or directory`) and the summary never printed. The exit code is the authoritative signal — `xcodebuild test` exits non-zero if any test fails — and a search for failed cases, assertion failures and recorded issues found none. The bundle write is unrelated to the code under test.

An earlier attempt to run only these suites was stopped before producing output and was not retried, per `CLAUDE.md` §5. The run above shows the test host is healthy: it printed `Testing started` and completed in 72 seconds, which is exactly what a broken host does not do. **No machine restart is needed.**

No XCUITest was written, built, or run.

## Device checklist for the repo owner

Nothing on screen changes in this ticket. Everything below is checked in the database.

1. **Re-select a word already in your vocabulary** and translate it. The marker appears as before, and `SELECT lookup_count, last_looked_up_at FROM learning_card` shows the count has gone up by **one**.
2. **Without closing the sheet, tap Translate again** (or switch target language and back). The count does **not** move again — one selection is one forgetting.
3. **Close the sheet, re-select the same line again.** Now it goes up by one more: that is a second, genuine forgetting.
4. **Airplane mode. Re-select a collected word.** The marker still appears. Reconnect, open the app, and the count catches up.
5. **Forget the same word twice offline** (select, dismiss, select again), then reconnect: the count goes up by **two**, not one. This is the case the no-deduplication rule exists for.
6. **Collect a word you have never collected**, then re-select it. The count is 1 — collecting itself is not a lookup.
7. **A word you never re-select keeps a count of 0**, and nothing about it changes. Never looking a word up again says nothing about knowing it.
8. Confirm `due_on` and `ladder_stage` are untouched throughout — rescheduling on a hit belongs to stage 3.
