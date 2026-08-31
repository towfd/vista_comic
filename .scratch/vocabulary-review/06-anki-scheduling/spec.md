Status: ready-for-agent

# Vocabulary stage 6: a scheduler that remembers between sittings

Stage 6 of `.scratch/vocabulary-review/prd.md`, and the largest revision the PRD has taken. It
replaces the review model wholesale: the three-step day goes, learning steps arrive, the ladder
becomes an interval table, and practice starts working offline.

It exists because of a question asked during the first real acceptance pass — *"I have practised
this card several times and it still says New, why?"* — and because the answer turned out to be
the model rather than a bug in it.

## Problem Statement

**Progress inside a day is thrown away at midnight.** The three-step day (不熟 → 熟悉 → 通過) is
derived by replaying *today's* rows, so a card left at 熟悉 when the reader put the phone down is
back at first appearance the next morning. Two of the reader's answers bought nothing. This is
the mechanism behind the complaint above: part of it was a stale deck (fixed in #86) and the rest
is this — the day's work was never carried forward.

**The only thing that survives a day is the ladder, and it barely moved.** Until #86 a single
wrong answer sealed a card for the whole day, so a fresh deck could not climb out of the first
rung at all. Even after the fix, one rung per day is the ceiling.

**A wrong answer leaves the sitting.** Nothing brings the card back a few minutes later, which is
the single most useful thing a scheduler can do with a mistake. The PRD's answer to this was a
separate 錯題區; this spec's answer is that the scheduler should not have dropped the card in the
first place.

**The round is ten questions because ten is a number.** Session length is arbitrary rather than
derived from what is actually due, so the reader cannot tell whether they are finished.

**Practice does not work offline.** `OfflineFallbackStudyRepository.recordReview` passes straight
through to the API and throws when it cannot be reached, while collecting words and lookups are
both queued. The one activity the reader would most want on a train is the one that requires a
tunnel.

## Solution

Adopt the model Anki uses, which is SM-2's, with this project's binary grading:

1. **Learning steps.** A new card is shown, and each correct answer advances it 5 → 7 → 10
   minutes. After the last step it graduates onto the interval table. A wrong answer sends it
   back to the first step.
2. **Seven interval slots** — 1 / 3 / 7 / 21 / 60 / 150 / 365 days — climbed one per correct
   answer once graduated.
3. **A lapse costs one slot, not everything.**
4. **A session runs until the queue is empty**, not for ten questions.
5. **Two entrances**: 複習卡片 (scheduled) and 永無止盡的訓練 (random, changes nothing).
6. **Answers are written locally first**, so the whole loop works with no network.

## User Stories

- As a reader who got a card wrong, it comes back a few minutes later in the same sitting instead
  of vanishing until tomorrow.
- As a reader who stopped halfway through, the cards I had half-learned are still half-learned
  when I come back.
- As a reader, the session ends when there is nothing left to do, and I can see that it ended.
- As a reader on a train with no signal, I can still practise, and my answers are not lost.
- As a reader looking at my deck, each row tells me what the system actually knows about that
  card — its state and when it is next due — rather than an adjective.
- As a reader who has finished today's cards, I can keep practising without disturbing the
  schedule I just earned.

## Implementation Decisions

### Learning steps replace the three-step day, not the ladder

The reader's initial framing was that the ladder would no longer be needed. It is the other way
round: learning steps are what happens *before* a card graduates, and the ladder is the interval
table it graduates onto. What they replace is 不熟 / 熟悉 / 通過, and — more importantly — the
daily reset that made that ladder pointless.

`daily_progress.py` is deleted in full.

### Seven slots, and why 90 then 120 was rejected

The reader proposed extending 1/3/7/21/60 with 90 and 120. That flattens the curve: 60 → 90 is
×1.5 and 90 → 120 is ×1.33, both below the table's own average ratio of about ×2.8, which would
say that surviving 60 days makes a card *less* stable. SM-2 grows intervals multiplicatively
(`I(n) = I(n-1) × EF`, EF defaulting to 2.5, which is also Anki's default starting ease), so the
consistent continuation is **150 and 365**.

365 is the terminal slot: a card asked once a year is retired without being deleted.

The table is **not adjustable in this stage**. Nothing is bound to it any more (question types
stopped reading the rung — see below), so opening it carries no technical risk; it is closed
because the reader has not yet used the new model and has no specific complaint about those seven
numbers to aim a setting at.

### A lapse falls one slot

A graduated card answered wrong re-walks the learning steps and, on graduating again, returns to
the **previous** slot rather than the first: 60 → 21, not 60 → 1.

The old ladder dropped to the bottom. That was defensible when a wrong answer was rare, and is
not now that judging is exact-match on production: an otherwise perfect Vietnamese sentence with
one word out of place is wrong, and charging a year of progress for it teaches nothing. Tones are
already forgiven (`SentenceAnswer.swift`), so this is the remaining sharp edge.

Relearning reuses the same 5/7/10 steps. Anki keeps a separate, shorter relearning step list;
that is one more setting to explain and verify, and this deck is not big enough to notice.

### Question type is random, with no floor

`askedDifficulty(forRung:)` is deleted. A card is asked in any mode it supports, chosen at
random — `askableModes` already computes exactly that set in its fallback path.

This was the reader's decision, made against a recommendation to keep a floor, and the
recommendation was withdrawn once the facts were checked: **tones are forgiven and count as
correct** (`ClozeQuestion.swift:154`), which the PRD had wrong, so a first-sight sentence card
asked to be typed is hard rather than impossible. A card that cannot be produced yet will still
be drawn as a rearrangement or a four-choice cloze often enough to graduate; it takes longer,
which is the intended difficulty.

There is deliberately **no leech rule** and no "asked three times, bury it". If a session becomes
unfinishable in practice, the stop button is the release valve and the rule can be added then.

### The session ends when the queue empties

A session is over when nothing is due now, nothing is due inside the learn-ahead window, and the
day's new-card quota is spent. That end is the reader's reward for showing up, and a fixed
question count cannot produce it.

**Learn-ahead is 20 minutes**, Anki's default, and is not a setting. It only fires when learning
cards exist but none has come due — without it a deck this small would sit idle waiting out a
5-minute timer with nothing else to ask.

The reader can stop at any point and **nothing is rolled back**: a card on step 2 stays on step
2. Removing the penalty for leaving is the whole reason the state is stored.

### New cards: 15 a day, no carry-over, learning cards exempt

The quota counts cards **first answered today**. A card introduced yesterday and still in the
learning steps does not consume today's quota — if it did, yesterday's stuck cards would crowd
out today's new ones and the deck would introduce fewer and fewer words.

Unused quota does not accumulate. Ten unused today does not make 25 tomorrow; accumulation
manufactures a backlog to catch up on, and the reader's existing once-a-day habit is worth more
than the arithmetic.

Due cards have **no cap**, by the reader's decision. The worst case — a heavy due day plus 15 new
cards — is answered by the stop button rather than by a limit.

### 永無止盡的訓練 changes nothing about the schedule

The second entrance draws at random from every card whose state is not *new*, in any supported
question mode, avoiding only the same card twice in a row. It has no end.

It **does not reschedule anything**, by the reader's decision, taken against the objection that a
card forgotten in training is evidence the schedule is wrong and is being discarded. Recorded
here so that if training later feels like shouting into a well, the reason is on file.

Its answers are still written to `card_review`, marked `context = 'training'`. The log has been
complete since stage 1 specifically so that adopting FSRS later is an algorithm change and not a
migration, and a log that cannot distinguish a scheduled answer from a free-practice one is not
complete.

**One column per row, not a token prefix and not a session table.** Encoding the mode into
`client_token` would overload an idempotency key with meaning, force `LIKE` queries, and
misfile rows silently whenever the format changed. A session table has a lifecycle problem —
sessions abandoned when the app is killed, and a training mode that by definition never ends. A
`card_review` row is meant to be legible on its own; needing a join to know what it was is a
worse trade than one string column. If stage 7 wants per-session statistics, a nullable
`session_id` can be added then as a pure addition.

### Card state is stored, not derived

The three-step day was derived by replay, on the argument that a stored state has a settlement
moment and a settlement moment can run late, twice, or not at all. That argument does not survive
two facts of this stage:

- A learning card's position — which step, and due at what minute — is a dimension the log has
  never carried. Replay can recover a slot; it cannot recover a timer.
- **The migration resets every card while keeping every review row.** After it, cards exist with
  twenty answers on record and the state *new*. "Has no reviews" therefore stops being a
  definition of newness.

So `learning_card` gains an explicit state, and the state is authoritative.

### The client supplies the answer's timestamp

`card_review.reviewed_at` is the server clock today. With offline practice, an answer given at
09:00 on a plane and flushed at 17:00 would be scheduled from 17:00, and minute-level steps would
be nonsense. The app sends `answeredAt`; the server stores it rather than `now()`. `local_date`
keeps its existing job of grouping by the reader's day.

### Offline practice follows the queue pattern already in the repo

`PendingCardStore`, `PendingLookupStore` and `PendingProgressStore` are all the same shape:
persist locally, flush when the network returns. Answers become the fourth.

**Every answer is written the moment it is given**, not at the end of a session. An answer is an
event that cannot be reconstructed, and the reader's proposal to save on exit would lose a whole
sitting to a crash while also making leaving the app feel expensive — the opposite of what the
"stop any time" rule is for.

The local deck snapshot (`DeckSnapshotStore`) carries the scheduling state too, so the queue can
be built with no network. On flush, the backend recomputes from the same rules and its answer
**wins**; `uq_card_review_client_token` already makes a resubmission harmless.

The two sides agree because scheduling is a pure function of the card's state and the answers
against it — the one property of the replay design worth keeping.

### Settings live on the backend and are not editable offline

The adjustable values are the **learning steps** (a list, so the number of steps is adjustable
too, not just the minutes) and the **new cards per day**. They live in one backend row; the app
caches them.

They have to be one copy: the backend recomputes schedules on flush, and two devices holding
different steps would produce different `due_at` values for the same answers.

Editing requires a connection. `OfflineFallbackStudyRepository` already refuses to queue edits
and deletes, on the grounds that offline edits have no derivable merge rule — only an invented
one. Settings are rarer than card edits and the same argument applies with more force.

### Rows show state and time, not an adjective

`Familiarity` is deleted. A row reads `新卡`, `學習中 2/3 · 7 分鐘後`, `21 天 · 3 天後到期`, or
`重新學習 1/3`. The mid-question readout added in #86 shows the same thing.

The adjectives were an alias for the rung, which is why a screen full of `Familiarity New` was
the thing that finally provoked this rewrite: the word described a column that had not moved, and
looked like a judgement of the reader.

### Migration resets every card

Every card becomes *new*, at slot 0, due immediately. **Every `card_review` row is kept** — it is
history, not state.

Chosen over preserving slots because the ladder could barely climb before #86, so almost nothing
has been earned, and because the reader confirmed the same reset should run against the real
database on their other machine.

## Data model

`learning_card`
- **add** `state` (`new` / `learning` / `review` / `relearning`)
- **add** `learning_step` (index into the steps list; null outside learning states)
- **add** `due_at` (timestamptz) — **replaces** `due_on`
- **add** `previous_stage` (the slot to return to after a lapse; null when never lapsed)
- `ladder_stage` **kept**, re-read as "which interval slot", now 0–6
- **drop** `last_ladder_move_on`

`card_review`
- **add** `context` (`review` / `training`)
- **add** `answered_at`, supplied by the client; `reviewed_at` stays as the receipt time

`study_settings` (new, single row like `comprehend_usage`'s natural key)
- `learning_steps` (minutes, ordered), `new_cards_per_day`

Deleted: `daily_progress.py`, `countsTowardLadder`, `practiceRoundLength`, the round's top-up and
appearance limits, `askedDifficulty`, `Familiarity`.

## Out of Scope

- **錯題區** — cancelled. Learning steps do its job inside the sitting, and the PRD's separate
  mistakes area would now be a second scheduler disagreeing with the first.
- **翻牌 (matching)** — dropped entirely, not deferred. It was the easiest of the four question
  types, and 永無止盡的訓練 covers the "practise without consequences" need it was there for.
- **Ease factors, per-card difficulty, FSRS.** Grading is binary; SM-2's EF needs a four-way
  self-rating this app deliberately does not ask for.
- **An adjustable interval table.** See above.
- **Notifications.** Nothing tells the reader a 5-minute card came due; the app has no
  notification code at all and this stage adds none.
- **Streak, XP, per-session statistics** — stage 7.

## Verification

Per `CLAUDE.md`:

- Inspect the git diff each increment and confirm unrelated work is untouched.
- Backend: pytest over the scheduler, the store and the routes. The scheduler is a pure function
  and must be tested as one — every transition (new → learning → review, lapse → relearning →
  previous slot, quota, learn-ahead) is a unit test, not a device check.
- iOS: the queue engine is plain Swift and tested in `vista_comicTests`. **No XCUITest is
  written, built or run.**
- Test runs follow `CLAUDE.md` §5: five-minute budget, one kill, hand back.
- UI verification is the reader's. Each ticket ends with a specific device checklist; tickets 4–8
  are where the behaviour becomes visible.

## Tickets

| # | Ticket | Verifiable by |
|---|---|---|
| 01 | Schema, migration, and the scheduler as a pure function | tests only |
| 02 | The endpoints the scheduler runs on | curl |
| 03 | The queue engine on the device | tests only |
| 04 | 複習卡片: a session that ends when it is finished | device |
| 05 | 永無止盡的訓練 | device |
| 06 | Settings | device |
| 07 | Answering with no network | device, in airplane mode |
| 08 | What a card says about itself | device |
