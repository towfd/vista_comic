# 01 — Record every answer

**What to build:** `card_review` and the endpoint that writes to it. One row per answer: which card, which question type, right or wrong, when, and how long it took.

Nothing changes on screen. It goes first because everything else in this stage is a function of these rows — the three-step day is derived from them, the ladder moves because of them, and stage 7's 錯題區 reads them. Until they exist there is nothing to compute from.

**`elapsed_ms` is recorded but not used.** The PRD keeps the review log complete so that swapping the ladder for FSRS later is an algorithm change rather than a data migration, and response time is the signal FSRS wants that nothing here reads. Collecting it costs a column; collecting it *retroactively* is impossible.

**A retried submission must not count twice.** The app queues nothing yet, but a tapped button on a slow connection is exactly how one answer becomes two — and a duplicated wrong answer would drop a rung the reader never lost.

**Blocked by:** nothing.

**Status:** implemented on branch `feat/review-log`, 2026-08-20 — backend `280 passed`. Nothing calls it until ticket 04.

- [x] An Alembic revision creates `card_review`, and downgrades cleanly
- [x] `POST /cards/{id}/reviews` records an answer and returns it
- [x] The row carries the card, the question type, whether it was correct, when, and the elapsed milliseconds
- [x] An unknown card is 404, not a row with a dangling reference
- [x] Deleting a card takes its reviews with it — they describe a card that no longer exists
- [x] A resubmitted answer does not produce a second row
- [x] `GET /cards/{id}/reviews` returns a card's reviews, oldest first, so the day can be replayed
- [x] A store failure surfaces as 503, matching the resource's existing shape

## What was built

`card_review`, `card_review_store`, and `POST`/`GET /cards/{id}/reviews`, with `learning_card.last_ladder_move_on` for ticket 03's once-a-day cap.

**The row carries two dates, and that came out of a failing test.** The day was first grouped by `reviewed_at`, the server clock — but the boundary that matters is the reader's local midnight. On UTC+8, grouping by the server would put everything before 08:00 on the previous day, so a card passed before breakfast could be passed again after it and climb two rungs in one felt day. `local_date` is sent by the app and is what the day is grouped by; `reviewed_at` orders a replay and is the timestamp FSRS would want.

**Idempotency has a matching pair of tests**, and the second is the one that is easy to leave out: the same token twice records once, and **two different tokens both record**. A card is asked more than once in a round and passing needs two correct answers counted — an over-eager dedupe would mean the reader could never pass anything.
