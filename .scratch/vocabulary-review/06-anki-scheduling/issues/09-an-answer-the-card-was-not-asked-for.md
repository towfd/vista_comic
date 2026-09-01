Status: implemented on branch `feat/practice-ui`, 2026-09-01

# 09 — An answer the card was not asked for

**The report.** A card answered four times in one session graduated onto slot 0, and should
have been due in a day. It came up a fifth time, was answered correctly again, and is now due
in **three** days.

**What happened.** Three days is slot 1, and the only path to slot 1 is `next_schedule`'s
`REVIEW` branch — a card already on the interval table, answered correctly. So the card took
five scheduled answers: the fourth graduated it, the fifth promoted it. The scheduling is not
wrong. **The fifth question is.**

**Why it was asked.** `PracticeQueue.nextCard` reads the session's local `deck`, and that deck
is only corrected when an answer's response comes back:

- `PracticeView.swift:540` — the submission is `Task { await submit(...) }`, fire-and-forget.
- `PracticeView.swift:498` — "Next" does not wait for it. `advance()` reads whatever `deck`
  holds at that moment.
- `PracticeView.swift:555` — `try?` swallows the failure, so `deck[index].apply(result)` never
  runs and the card stays `learning`, `dueAt <= now`, **for the rest of the session**. Nothing
  refetches mid-session.

One dropped response is therefore enough to guarantee the card is asked again — and with a
small deck it is not even a race, because `pick()` falls back to the whole candidate list when
avoiding the previous card would leave nothing.

**And nothing downstream refuses it.** `card_review_store.apply_answer` applies whatever
arrives to whatever state the card is in. It stops the same `clientToken` twice; it cannot stop
the same card being asked twice with two tokens. Both sides are missing the same judgement:
*this card is not due.*

## What to build

**1. The rule, in `scheduler.next_schedule` (authority).** A `REVIEW` card whose `answered_at`
is before its `due_at` is returned **unchanged** — no promotion, no lapse, no new due date. The
answer is still recorded; it just moves nothing, exactly as a training answer does.

Answering early proves nothing about the interval being tested: a card that graduated onto "one
day" an hour ago has not survived a day, and promoting it to three teaches the schedule
something that did not happen. Not lapsing on an early wrong answer follows from the same
sentence — an answer that cannot earn anything must not cost anything either.

The learning steps are deliberately **not** covered by this. `learnAheadWindow` offers a
learning card up to twenty minutes early on purpose, and a duplicate there costs one step and
heals itself.

**2. The same rule in `Scheduler.swift`**, pinned by `SchedulerParityTests` like every other
row of the table.

**3. Stop asking twice, in `SessionView`.** Apply the local transition to `deck` the moment the
reader answers, using the Swift table that already exists, and let the server's outcome
overwrite it when it arrives. The offline path already runs on that table; this makes online and
offline agree instead of leaving the online session's queue depending on a round trip.

- [x] A `REVIEW` card answered correctly before it is due keeps its slot, state and `due_at`
- [x] The same, answered wrong: also unchanged
- [x] Answered on or after `due_at`: promotes and lapses exactly as before
- [x] A learning card answered early still advances (the learn-ahead window is intact)
- [x] The Swift twin agrees, in the parity tests
- [x] The queue does not offer a card whose answer is still in flight
- [x] A failed submission does not leave the card due for the rest of the session

## Verification the user owns

On a device, in one session: take a card through its steps until it graduates, then keep
answering until the queue is empty. It must not come back that day, and 單字庫 must still say
`1 天` afterwards. Cross-check with `GET /cards/{id}/reviews` — five `review` rows for one card
in one sitting is the bug reproducing.

## What was built

One rule, in both schedulers: `answered_at < due_at` on a `REVIEW` card returns it unchanged.
`scheduler.py`'s branch and `Scheduler.swift`'s twin, with the parity suite carrying three new
cases — early and correct, early and wrong, and the boundary (`answered_at == due_at` still
moves, because a card due at eight answered at eight is on time).

`SessionView` now moves its deck on the tap rather than on the response. `answer(_:)` runs the
Swift transition table over the card and hands the same instant to `submit`, which overwrites it
with the server's outcome when that arrives. The queue therefore never reads a card the session
has already answered, whether the response is slow, lost, or refused.

**Three endpoint tests had to be rewritten, and that is the finding.**
`test_a_graduated_card_climbs_on_every_correct_answer` walked a card to the top of the table by
answering it twenty times in the same millisecond, and it passed. It was asserting the bug. They
now answer at each card's due date via `_answer_when_due`, which is what a reader does over
twenty sittings, and two new tests hold the guard directly.

What the old test's docstring claimed — "what keeps this honest is that a graduated card is
scheduled a day out and the round will not offer it again" — was true of the queue's intent and
false of what the queue could guarantee. The scheduler trusted the client. It no longer does.
