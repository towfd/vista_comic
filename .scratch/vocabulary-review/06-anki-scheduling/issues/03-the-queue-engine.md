Status: ready-for-agent

# 03 — The queue engine

**What to build:** The pure Swift that decides what to ask next and when a session is over.
No views.

Given the deck, the settings, and the current time, it produces the next question or reports that
the session is finished. `makeRound` is replaced, not extended: fixed length, top-up,
`appearances < 2` and the `isDue`-then-rung ordering all describe a model that no longer exists.

Order of preference: cards due now (learning and relearning first, since minutes matter more than
days), then review cards past `dueAt`, then new cards up to the remaining quota, then —
**only if learning cards exist but none is due yet** — the learning card closest to due, provided
it is within the 20-minute learn-ahead window.

The session is over when all four are empty. There is no other end condition; the reader stopping
is not the session ending, and nothing is rolled back when they do.

**Quota counts cards first answered today**, in the reader's local day, from the deck's own state
rather than a counter: a card is "introduced today" if it left `new` today. Cards already in
`learning` from yesterday do not consume it.

**Question mode is drawn at random** from `askableModes`, which loses its rung filter and becomes
"everything this card supports". `askedDifficulty` is deleted.

**Blocked by:** 02.

- [ ] Learning cards due now come before review cards due now
- [ ] A card due in 3 minutes is offered when nothing else is available, and not when something is
- [ ] A card due in 40 minutes is never offered early
- [ ] New cards stop at the quota, and yesterday's unfinished learning cards do not count against it
- [ ] Unused quota does not carry into the next day
- [ ] The session reports finished only when due, learning, new and learn-ahead are all empty
- [ ] Mode selection can return any mode the card supports and never one it cannot
- [ ] A deck of one card still produces a session rather than an empty one
- [ ] `askedDifficulty`, `practiceRoundLength` and the top-up path are gone
- [ ] A cached deck snapshot written before stage 6 — `dueOn`, no `dueAt` — still decodes
      rather than emptying the deck (moved here from ticket 02, where the API has no snapshot)
