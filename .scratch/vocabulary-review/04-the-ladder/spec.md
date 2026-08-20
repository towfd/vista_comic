Status: ready-for-agent

# Vocabulary stage 4: the ladder, and a day that can be passed

Stage 4 of `.scratch/vocabulary-review/prd.md`. Stage 3 made a round playable and deliberately
recorded nothing. This is where answers start to mean something.

## Problem Statement

A round is currently a toy. It asks five questions, shows whether each was right, and forgets
all of it — so the same cards can come up tomorrow, and the day after, in the same order,
whether or not the reader knows them. Nothing gets easier, nothing retires, and **playing twice
is the same as playing once**.

That was the correct thing to build first: it proved the questions are answerable before any
machinery was built to remember them. But it means the app still cannot answer the only
question that matters over weeks — *is this working?* — because it keeps no record of what
happened.

## Two clocks, and they are genuinely separate

The design settled in the PRD has two systems running at different speeds, and most of the
difficulty in this stage is keeping them apart.

**Within a day, a card climbs three steps.** It resets daily and describes *this session's*
recall:

| Now | Correct → | Wrong → |
|---|---|---|
| first appearance today | **熟悉** (skips 不熟) | 不熟 |
| 不熟 | 熟悉 | 不熟 |
| 熟悉 | **通過** | 不熟 |

So a card needs **two correct answers in a row to pass the day**, and a round of five questions
is not five distinct cards.

**Across days, a card climbs the ladder**: 1 / 3 / 7 / 21 / 60 days. It moves **at most once per
day**, and what moves it is the day's first resolution — not each answer. Correct advances one
rung; **wrong drops to the first**, not by one.

Dropping to the bottom was the PRD's original rule and is restored here after it drifted during
planning. The alternative — down one rung — means a card forgotten at 60 days is next asked in
21, which is a long time to wait after just proving it is gone.

## Solution

1. `card_review` — every answer, recorded.
2. The three-step day, derived from today's reviews rather than stored.
3. The ladder, moving once per day.
4. A round of **ten** questions that requeues a wrong answer until it is right, and selects by
   what needs practice.

## User Stories

- As a reader, a word I get right twice today stops coming up for a while, and a word I miss
  comes back tomorrow.
- As a reader who got something wrong, it comes back later in the same round until I get it
  right — so I never leave a round having simply failed at something.
- As a reader who has been away for three days, nothing was lost and nothing needs catching up;
  the words that were due are still waiting.
- As a reader, the words I am worst at come up first.

## Implementation Decisions

### The day's state is derived, not stored

A card's three-step position is computed by replaying **today's** reviews of it in order. There
is no column holding 不熟/熟悉/通過, and no job that resets one.

This is what makes "away for three days" cost nothing. There is no settlement moment, so there
is nothing to run late, nothing to run three times, and no question about what a missed day
should have done. **A day the reader did not practise is simply a day with no reviews in it.**

### Not practising is not failing

A due card that is never answered does not drop. It stays due, keeps its place in the priority
order, and waits.

This follows directly from the PRD's rule that the ladder is a priority ordering rather than a
promise: at fifty cards a week, more will be due than any session can hold, and a system that
punished the reader for the arithmetic would be punishing them for collecting.

### The day's first resolution wins

The ladder moves on the **first** of these to happen to a card on a given day:

- an answer is **wrong** → drop one rung
- the card reaches **通過** → advance one rung

Whichever comes first is the day's move, and the other cannot happen afterwards.

**So a card answered wrong at the start of a round does not recover its rung by being drilled to
通過 later that day.** That is deliberate and worth stating plainly, because it will feel harsh
in the moment: the reader *did* end the session knowing the word.

The reason is what the two clocks measure. The three-step day is about recall in this session —
and practising until it sticks is exactly what it is for. **The ladder is about recall after a
gap**, and the gap already happened: the reader met the word today and did not have it. Letting
an afternoon of drilling erase that would make the ladder a record of effort rather than of
memory, and the interval it schedules would stop meaning anything.

`learning_card` gains `last_ladder_move_on`. The once-per-day cap cannot be derived from the
reviews, because a review does not know whether it was the one that moved the rung.

### A wrong answer comes back until it is right

Within a round, a wrong answer is requeued and asked again later, and the round is over when all
five have been answered correctly once. A round therefore has no fixed length beyond its five
items.

The reader never leaves a round having failed at something — which is the point, and is also why
the ladder can afford to be strict about that first wrong answer.

### Selection: the least familiar first, with two guards

Cards are drawn from those due, in priority order, least familiar first. **The reader's worst
words come up first**, for two reasons: a wrong answer is not a dead end here, so the usual
argument about discouragement does not apply; and a card at 熟悉 needs one more correct answer
while a card at 不熟 needs two, so favouring the nearly-learned would flatter the round's numbers
while teaching less.

Weighting purely by unfamiliarity deadlocks, though — the least familiar card always wins, and
getting it wrong makes it win harder. Two guards:

- **A card never appears twice in a row.**
- **A card appears at most once per answer mode in a round**, so at most twice. This is also the
  only way a card reaches 通過 inside a single round, since passing needs two correct answers.

**A round is ten questions, not five** (changed from stage 3's length). At two appearances per
card, five would let at most two cards pass — and with thirty cards all sitting on the first rung
on day one, that is fifteen rounds to get through the deck once. Ten lets four or five pass while
staying inside the two-or-three minutes the PRD asks for. Cards that do not fit simply queue: the
ladder is a priority ordering, not a promise.

### What still does not move the ladder

Unchanged from the PRD, and worth restating because this is the stage where it becomes possible
to get wrong:

- **Cards topped up into a round when too few are due move nothing**, in either direction.
- Matching, when it exists, moves nothing. It is a warm-up between the demanding types.

## Testing Decisions

The three-step machine and the ladder are pure functions over a list of reviews, and carry most
of the tests:

- Every transition in the table above, including first-appearance-correct skipping 不熟.
- Two correct in a row passes; correct-wrong-correct does not.
- Replaying yesterday's reviews has no effect on today's position.
- The ladder advances one rung on 通過 and **drops to the first rung** on a wrong answer, from
  any height.
- It moves **once**: wrong-then-通過 on the same day leaves the rung dropped.
- A card with no reviews today keeps its rung and its due date, however many days have passed.
- The top and bottom rungs clamp rather than overflowing.
- A due date is computed from the rung reached, not from the rung left.

Round mechanics:

- A round is ten items; a wrong answer is requeued and the round ends only when every item has
  been answered correctly.
- A card never appears twice consecutively, and at most twice per round.
- Selection prefers the least familiar.
- Cards topped up beyond the due set are marked so their answers move nothing.

Backend: the review endpoint records what it is given, rejects an unknown card, and is
idempotent enough that a retried submission does not count twice.

**No XCUITest is written, built, or run.** UI verification is handed over as a checklist.

## Out of Scope

- 錯題區 and 單字練習 (stage 7). A wrong answer is *recorded* here, and stage 7 reads those
  records; nothing displays them yet.
- Matching and sentence translation as question types (stages 5 and 7).
- Practice-sentence generation (stage 6).
- Streaks, XP, and anything counting days (stage 8).
- Offline practice. A round needs the backend, as stage 3's did.
- Any adjustment of the intervals. 1/3/7/21/60 is a starting guess and stays one until there is
  real data to argue with.

## Further Notes

This stage is where the PRD's premise finally becomes testable. Until now the app could not tell
whether it was working; after this it holds a record of every answer, which is what the later
stages weigh and what the developer can look at in a month to decide whether the third attempt
at this feature deserves a fourth.
