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

**Status:** not started.

- [ ] Every transition in the table, asserted individually
- [ ] A first correct answer reaches 熟悉, skipping 不熟
- [ ] Two correct in a row reaches 通過
- [ ] Correct, wrong, correct does **not** reach 通過 — it ends at 熟悉
- [ ] A wrong answer from 熟悉 returns to 不熟, not to first-appearance
- [ ] Yesterday's reviews do not affect today's position, however many there were
- [ ] A card with no reviews today is at first appearance, not at 不熟
- [ ] Reviews are replayed in order; the same rows shuffled give the same answer only when the order is the same
- [ ] The function takes rows and a date, touching no repository
