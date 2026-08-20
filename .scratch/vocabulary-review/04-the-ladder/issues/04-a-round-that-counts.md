# 04 — A round that counts

**What to build:** The round becomes ten questions, requeues what was wrong, selects by what needs practice, and records what happened.

**Ten, not five.** At two appearances per card, five questions would let at most two cards pass — and with thirty cards on the first rung on day one, that is fifteen rounds to get through the deck once. Ten lets four or five pass while staying inside the two-or-three minutes the PRD asks for.

**A wrong answer comes back until it is right.** The round ends when all ten items have been answered correctly once, so a round has no fixed length beyond its ten items. The reader never leaves having simply failed at something — which is also why the ladder can afford to be strict about that first wrong answer.

**Least familiar first**, because a wrong answer is not a dead end here so the usual argument about discouragement does not apply, and because a card at 熟悉 needs one more correct answer while a card at 不熟 needs two — favouring the nearly-learned would flatter the round's numbers while teaching less.

Weighting purely by unfamiliarity deadlocks, so two guards: **a card never appears twice in a row**, and **at most once per answer mode**, which is also the only way a card reaches 通過 inside one round.

**Cards topped up beyond the due set move nothing**, in either direction. The reader cannot tell them apart, and that is fine: the difference is about scheduling correctness, not about their experience.

**Blocked by:** 03.

**Status:** implemented on branch `feat/review-log`, 2026-08-20. **Awaiting the repo owner's device pass** (checklist below).

- [x] A round is ten items and ends only when every one has been answered correctly
- [x] A wrong answer is requeued and asked again later in the same round
- [x] A card never appears twice consecutively
- [x] A card appears at most once per answer mode, so at most twice
- [x] Selection prefers the least familiar card among those due
- [x] Too few due cards tops the round up, and those answers move no rungs
- [x] Every answer is recorded, including the requeued ones
- [x] The summary reports how many cards passed the day, not just how many answers were right
- [x] Leaving mid-round loses the round but keeps the answers already recorded
- [x] A round can be played again immediately, and the second round sees the first round's results
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `PracticeItem` gains `isDue` and a per-item `token`, so a requeued attempt is its own answer rather than a replay of the first — which matters, since passing needs two counted correct answers.
- `makeRound` orders by due-then-least-familiar, with the two guards.
- `RoundView` submits each answer, requeues the wrong ones, and reads the step and rung **from the response** rather than recomputing them.
- `RoundOutcome` reports **cards passed**, not a score.

**Three decisions worth review:**

1. **The summary counts words done, not answers right.** A round can be answered perfectly and pass nothing — if every card came up once — and a reader shown "10 / 10" would reasonably think they had finished something. `.unknown`, which is what a failed submission yields, counts as nothing: telling them they finished a word the server never heard about would be worse than saying less.
2. **Progress reads "3 of 10 left" rather than "3 of 10".** A requeued item moves the total, and a progress readout that goes backwards reads as a bug.
3. **A failed submission costs the record, not the round.** The reader is mid-question and there is nothing they could do; the answer they gave stands on screen either way.

`StudyRepositoryDefaults.swift` was added along the way. Four test doubles conform to `StudyRepository`, each interested in one or two methods, and this was the fourth time growing the seam meant editing all four. A double stubbing a method it never calls is stating something it does not mean, and four copies of that drift.

## Device checklist for the repo owner

The deck is **30 cards, all on rung 0, all due today**, so nothing will be topped up on the first
run — every answer counts.

**Two of these cannot be repeated once done, so read them before starting.**

1. Open 練習. The card says ten questions.
2. Play a round. **Answer the first card correctly twice** (it comes back in the other mode).
   After the second, that word is done for the day.
3. **⭐ Answer one card wrong on purpose, early.** It comes back later in the round — answer it
   correctly twice. It will reach 通過 for the day, and **its rung will still be at the bottom**.
   That is the rule that feels harsh and is deliberate; this is the only way to see it.
4. Finish the round. The summary says **how many words are done for today**, not a score.
5. Check the database: `SELECT source_text, ladder_stage, due_on FROM learning_card ORDER BY
   ladder_stage DESC` — the words you passed are on rung 1 and due in three days; the one you
   missed is on rung 0 and due tomorrow.
6. **Play a second round immediately.** A word already passed today should not climb again —
   `ladder_stage` stays where it is however many rounds you play.
7. Mid-round, leave the tab and come back: the round is gone, but the answers you already gave
   are still recorded. Check `SELECT count(*) FROM card_review`.
8. **⭐ Tomorrow**, open 練習 again. The word you missed is due; the ones you passed are not.
9. Airplane mode mid-round: answering still works on screen, and the summary does **not** claim
   those words are done.
10. Both phone sizes: a long sentence with a blank wraps, and the four options do not overflow.
