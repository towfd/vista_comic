Status: ready-for-agent

# 01 — The scheduler, and what a card now remembers

**What to build:** The new scheduling rules as a pure function, the columns they read and write,
and the migration that resets the deck onto them.

The function takes a card's state (state, learning step, slot, previous slot), an answer, and the
settings, and returns the card's next state and `due_at`. It reads no clock of its own — the
answer's timestamp comes in as an argument, because ticket 07 will call it with a timestamp from
hours ago.

Transitions, in full:

| From | Correct | Wrong |
|---|---|---|
| `new` | `learning` step 0, due +5m | `learning` step 0, due +5m |
| `learning` step *i* (not last) | step *i+1*, due + that step | step 0, due +5m |
| `learning` last step | `review`, slot 0 (or `previous_stage` if set, then cleared), due +interval | step 0, due +5m |
| `review` slot *n* | slot *n+1* (clamped at 6), due +interval | `relearning` step 0, due +5m, `previous_stage` = *n−1* (floor 0) |
| `relearning` | same as `learning` | step 0, due +5m |

A card's first answer being wrong still puts it in `learning` — there is no punishment below the
bottom.

**The interval table is `(1, 3, 7, 21, 60, 150, 365)`.** `ladder.py` keeps its name and its shape;
`LADDER_INTERVALS` grows by two entries and `TOP_RUNG` follows. `move`, `rung_after_pass` and
`rung_after_failure` are replaced by the transition table above — the old ones encode "wrong goes
to the bottom", which is exactly what this ticket changes.

**Delete `daily_progress.py` and its tests.** Nothing derives a state by replay any more; the
reasons are in the spec under *Card state is stored, not derived*.

**The migration resets every card** to `new`, slot 0, `due_at` = now, `previous_stage` NULL. It
keeps every `card_review` row. `due_on` is dropped after `due_at` is populated;
`last_ladder_move_on` is dropped outright.

**Blocked by:** nothing.

- [ ] Every transition in the table above is a test, including the wrong-first-answer case
- [ ] A lapse from slot 6 returns to slot 5 after relearning, not slot 0
- [ ] `previous_stage` is cleared once used, so a second lapse from slot 5 returns to slot 4
- [ ] A lapse from slot 0 returns to slot 0 rather than to a negative slot
- [ ] The scheduler never calls `now()`; the timestamp is a parameter
- [ ] Settings are a parameter too — a three-step and a five-step list both schedule correctly
- [ ] Alembic upgrade adds the columns, backfills `due_at`, resets state, and keeps review rows
- [ ] Alembic downgrade is written and runs
- [ ] `daily_progress.py` and every reference to it are gone
