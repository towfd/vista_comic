# 02 — The three-step day

**What to build:** The rule that says where a card stands *today*: 不熟 → 熟悉 → 通過.

| Now | Correct → | Wrong → |
|---|---|---|
| first appearance today | **熟悉** (skips 不熟) | 不熟 |
| 不熟 | 熟悉 | 不熟 |
| 熟悉 | **通過** | 不熟 |

So **two correct answers in a row pass the day**, and one wrong answer anywhere puts the card back to the bottom of the day's steps.

**Derived from today's reviews, never stored.** There is no column holding the step and no job that resets one — the position is computed by replaying the day's rows in order.

That is what makes a gap cost nothing. **There is no settlement moment, so there is nothing to run late, nothing to run three times, and no question about what a missed day should have done.** A day the reader did not practise is simply a day with no rows in it, and three weeks away is the same as one day away.

A pure function over reviews, so it is testable without a database or a screen.

**Blocked by:** 01.

**Status:** implemented on branch `feat/review-log`, 2026-08-20 — 16 tests, all transitions covered.

- [x] Every transition in the table, asserted individually
- [x] A first correct answer reaches 熟悉, skipping 不熟
- [x] Two correct in a row reaches 通過
- [x] Correct, wrong, correct does **not** reach 通過 — it ends at 熟悉
- [x] A wrong answer from 熟悉 returns to 不熟, not to first-appearance
- [x] Yesterday's reviews do not affect today's position, however many there were
- [x] A card with no reviews today is at first appearance, not at 不熟
- [x] Reviews are replayed in order; the same rows shuffled give the same answer only when the order is the same
- [x] The function takes rows and a date, touching no repository

## What was built

`app/daily_progress.py` — `DailyStep`, `step_after`, `step_today`, `passed_today`. Pure functions over one day's answers.

**`unseen` and `unfamiliar` are different states.** A card never asked is not a card just failed; collapsing them would make every untouched card look like a failure, and a reader returning after a week would find their whole deck at the bottom.

The test worth reading is `test_correct_wrong_correct_does_not_pass`: passing needs two correct **in a row**, not two correct. Counting them would pass a card the reader missed in between — precisely the card the day exists to catch — and would do it silently.
