# 05 — Report how often a collected word is looked up again

**What to build:** Every time the reader selects a line they have already collected, that fact reaches the server.

Nothing displays this number in stage 1. It is collected now because it cannot be collected retroactively, and because it is the cleanest evidence this system will ever get that a word has been forgotten: the reader just proved it by looking it up again. Stage 2 shows it, stage 3 weights scheduling by it, stage 4 weights sentence generation by it. Starting the count later means those stages begin with a column of zeros.

**The negative is never inferred.** Not looking a word up again is not evidence of knowing it — the reader may simply not have reached that page. Only the positive is recorded.

**Do not touch `due_on`.** Rescheduling on a hit belongs to stage 3, where scheduling exists.

**One accepted imprecision**, recorded in `spec.md` and worth repeating in a code comment so it is not later mistaken for a defect: a report whose response is lost after the server commits will be retried and counted twice. Deduplicating it needs a per-event table, which is not worth paying for a counter that only feeds a weighting.

**Blocked by:** 03, 04.

**Status:** not started.

- [ ] A hit reports once per selection — not once per keystroke, re-render, or re-translate of the same selection
- [ ] The report is queued when offline and sent on reconnect, using the same flusher discipline as ticket 04
- [ ] `lookup_count` and `last_looked_up_at` reflect the reports
- [ ] `due_on` is left untouched
- [ ] A report for a card the server does not have is dropped rather than retried forever
- [ ] Not re-selecting a word changes nothing about it
- [ ] The double-count case carries a comment pointing at the spec rather than being treated as a bug
