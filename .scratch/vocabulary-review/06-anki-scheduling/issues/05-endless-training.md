Status: implemented on branch `feat/anki-offline`, 2026-08-31

# 05 — 永無止盡的訓練

**What to build:** The second entrance: random questions from cards the reader has already met,
forever, changing nothing.

Draws from every card whose state is not `new`, at random, avoiding the same card twice in a row.
Any supported question mode. No due dates, no quota, no end — the reader stops when they stop.

Answers are recorded with `context = "training"` and **must not move any schedule**. This is the
ticket where that is easy to get wrong by reusing the review path, so the check belongs in a test
rather than on the device: a card's `dueAt`, `state`, `learningStep` and `ladderStage` are all
identical before and after a training answer.

The screen should make it obvious this is practice and not the day's work, so the reader never
wonders whether they are damaging their schedule.

**Blocked by:** 04.

- [ ] Only cards past `new` appear; a freshly collected card never does
- [ ] A training answer leaves every scheduling field untouched
- [ ] A training answer still writes a `card_review` row, marked `training`
- [ ] The same card is never asked twice in a row
- [ ] With no eligible cards, the entrance explains why rather than opening an empty screen
- [ ] Both phone layouts

## What was built

Landed inside ticket 04's rewrite rather than after it: the second entrance is
the same `SessionView` with `mode == .training`, and building a separate screen
for it would have been two copies of one question flow.

`nextTrainingItem` draws at random from `trainableCards`, which is every card
past `new`. **The weighting rule the PRD specified — unfamiliarity raising a
card's chance, recent appearances suppressing it — was deleted rather than
built.** It was the most complicated rule in that document and it was serving
the one mode whose answers change nothing.

**The check that matters is a test, not a device pass.** A training answer
leaving `dueAt`, `state`, `learningStep` and `ladderStage` untouched is
invisible on screen — the reader would find out the next morning, from a
schedule that had quietly moved. It is pinned in three places: the backend route
(`test_card_reviews.py`), the wire format (`APIStudyRepositoryTests`, because a
missing `context` defaults to `review` and would silently reschedule), and the
offline replay (`PendingAnswerTests`).
