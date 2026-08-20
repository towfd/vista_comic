# 04 — A round that counts

**What to build:** The round becomes ten questions, requeues what was wrong, selects by what needs practice, and records what happened.

**Ten, not five.** At two appearances per card, five questions would let at most two cards pass — and with thirty cards on the first rung on day one, that is fifteen rounds to get through the deck once. Ten lets four or five pass while staying inside the two-or-three minutes the PRD asks for.

**A wrong answer comes back until it is right.** The round ends when all ten items have been answered correctly once, so a round has no fixed length beyond its ten items. The reader never leaves having simply failed at something — which is also why the ladder can afford to be strict about that first wrong answer.

**Least familiar first**, because a wrong answer is not a dead end here so the usual argument about discouragement does not apply, and because a card at 熟悉 needs one more correct answer while a card at 不熟 needs two — favouring the nearly-learned would flatter the round's numbers while teaching less.

Weighting purely by unfamiliarity deadlocks, so two guards: **a card never appears twice in a row**, and **at most once per answer mode**, which is also the only way a card reaches 通過 inside one round.

**Cards topped up beyond the due set move nothing**, in either direction. The reader cannot tell them apart, and that is fine: the difference is about scheduling correctness, not about their experience.

**Blocked by:** 03.

**Status:** not started.

- [ ] A round is ten items and ends only when every one has been answered correctly
- [ ] A wrong answer is requeued and asked again later in the same round
- [ ] A card never appears twice consecutively
- [ ] A card appears at most once per answer mode, so at most twice
- [ ] Selection prefers the least familiar card among those due
- [ ] Too few due cards tops the round up, and those answers move no rungs
- [ ] Every answer is recorded, including the requeued ones
- [ ] The summary reports how many cards passed the day, not just how many answers were right
- [ ] Leaving mid-round loses the round but keeps the answers already recorded
- [ ] A round can be played again immediately, and the second round sees the first round's results
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
