# 01 — Record every answer

**What to build:** `card_review` and the endpoint that writes to it. One row per answer: which card, which question type, right or wrong, when, and how long it took.

Nothing changes on screen. It goes first because everything else in this stage is a function of these rows — the three-step day is derived from them, the ladder moves because of them, and stage 7's 錯題區 reads them. Until they exist there is nothing to compute from.

**`elapsed_ms` is recorded but not used.** The PRD keeps the review log complete so that swapping the ladder for FSRS later is an algorithm change rather than a data migration, and response time is the signal FSRS wants that nothing here reads. Collecting it costs a column; collecting it *retroactively* is impossible.

**A retried submission must not count twice.** The app queues nothing yet, but a tapped button on a slow connection is exactly how one answer becomes two — and a duplicated wrong answer would drop a rung the reader never lost.

**Blocked by:** nothing.

**Status:** not started.

- [ ] An Alembic revision creates `card_review`, and downgrades cleanly
- [ ] `POST /cards/{id}/reviews` records an answer and returns it
- [ ] The row carries the card, the question type, whether it was correct, when, and the elapsed milliseconds
- [ ] An unknown card is 404, not a row with a dangling reference
- [ ] Deleting a card takes its reviews with it — they describe a card that no longer exists
- [ ] A resubmitted answer does not produce a second row
- [ ] `GET /cards/{id}/reviews` returns a card's reviews, oldest first, so the day can be replayed
- [ ] A store failure surfaces as 503, matching the resource's existing shape
