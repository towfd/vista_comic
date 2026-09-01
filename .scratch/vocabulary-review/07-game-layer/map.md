Status: parked, 2026-09-01 — paused by the repo owner partway through grilling

# Stage 7 — the game layer

Parked before a spec was written. The PRD (`.scratch/vocabulary-review/prd.md` §7) still
describes this stage as streak + daily completion + XP and levels, with per-comic mastery
optional. **Four decisions were taken before the pause and they are not all what the PRD
says**, so restart from this file rather than from the PRD.

## Decisions so far

| Question | Answer |
|---|---|
| What must the layer *cause*? | **Make the reader willing to do another round after finishing one.** Not "bring them back on a day they would not have opened the app" — that was offered as the recommendation and rejected |
| What is a round? | The repo owner defined it in passing as **every 5 questions in 永無止盡的訓練**, with milestone rewards for finishing new cards and finishing review. The unit does not exist today: stage 6 deliberately removed the fixed question count, and a session runs until its queue empties |
| Is XP a measure of learning or of participation? | **Participation, with very unequal weights and a daily cap.** Review correct >> new card learned > training per 5 questions. Collecting a card pays, but only for the first few each day. **Logging in pays nothing** |
| What counts as "today is done"? | **Two-tier.** Seven questions in any mode is *today's progress* — the moment that asks whether to keep going. Clearing the queue is a separate, heavier marker. A day with nothing due can be satisfied by training, because that is all there is to do that day |
| Streak | **Cut.** "連續記錄這個不用做 我沒興趣". Not deferred — the repo owner is not interested, and the rolling-window alternative was declined with it. The PRD's Game layer row is wrong on this point |
| Levels | Superseded by a **pet that grows with accumulated XP** — a growth stage is a level wearing a different word. Mechanically cheap |

## What stopped it

The pet's artwork. The repo owner raised the cost themselves ("這邊有點麻煩") and paused when
asked to choose between a programme-drawn placeholder shape, supplying real art, and splitting
the invisible half off into its own increment.

This repo has no character art — the visual assets are an app icon and four colours — so a pet
with growth stages needs images that only the repo owner can supply or licence. **That is the
blocker, and it is not a programming problem.**

## Two arguments made during the grilling that should survive the pause

1. **Paying XP for collecting a card attacks the PRD's quality gate.** "Tapping add *is* the
   quality gate" only holds while adding has no upside. The agreed answer keeps the payment but
   caps it per day; if this stage ever restarts, the cap is load-bearing rather than a tuning
   knob.
2. **Paying XP for training makes the highest-scoring strategy the one mode that moves no
   memory.** `nextTrainingItem` schedules nothing by design. The agreed answer is a rate low
   enough that grinding it is not worth it — again load-bearing, not a number to pick casually.

## Where to restart

The unanswered question is the one that paused this: what the pet looks like, and whether the
invisible half (XP records, the daily cap, the growth curve, today's progress) ships on its own
first.
