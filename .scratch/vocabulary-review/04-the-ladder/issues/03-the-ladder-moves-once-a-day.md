# 03 — The ladder moves once a day

**What to build:** The across-days schedule. 1 / 3 / 7 / 21 / 60 days, moving **at most once per day** per card.

The day's **first** resolution decides it:

- an answer is **wrong** → drop **to the first rung**, from whatever height
- the card reaches **通過** → advance one rung

Whichever happens first is the day's move, and the other cannot happen afterwards.

**So a card answered wrong early does not recover its rung by being drilled to 通過 later that day**, and that will feel harsh in the moment because the reader *did* end the session knowing the word. It is deliberate, and the reason is what the two clocks measure. The three-step day is about recall in this session — practising until it sticks is exactly its purpose. **The ladder is about recall after a gap, and the gap already happened**: the reader met the word today and did not have it. Letting an afternoon of drilling erase that would make the ladder a record of effort rather than of memory, and the interval it schedules would stop meaning anything.

**Wrong drops to the bottom, not by one.** A card forgotten at 60 days would otherwise be next asked in 21 — a long wait after just proving it is gone. This was the PRD's original rule and is restored after it drifted during planning.

**Not practising is not failing.** A due card never answered does not drop; it stays due and keeps its place. At fifty cards a week more will be due than any session holds, and punishing the reader for that arithmetic would be punishing them for collecting.

`learning_card` gains `last_ladder_move_on`. The cap cannot be derived from the reviews, because a review does not know whether it was the one that moved the rung.

**Blocked by:** 02.

**Status:** not started.

- [ ] Reaching 通過 advances one rung and sets the due date from the rung reached
- [ ] A wrong answer drops to the first rung from any height, including the top
- [ ] Wrong, then 通過 on the same day, leaves the rung dropped
- [ ] 通過, then a wrong answer on the same day, leaves the rung advanced
- [ ] A second 通過 on the same day moves nothing
- [ ] The top rung clamps rather than overflowing; the bottom rung clamps on a drop
- [ ] A card with no reviews keeps its rung and its due date, after one day or thirty
- [ ] A card answered while not yet due moves nothing, in either direction
- [ ] Due dates are computed from the day the move happened, not from the previous due date
