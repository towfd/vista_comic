# 10 — Today's deck on the overview

**What to build:** Opening `/practice` shows what is waiting today — how many cards are due, new, and in learning — worked out in the browser from the deck and settings the phone already uses. Nothing is written: this is the read-only foundation, and its numbers can be checked against the phone before any answer is ever posted. It brings the web's first calls about cards, the queue rules, and the store that holds the deck.

See the spec's *The queue* and *When the deck is fetched*. The phone's queue rules are inventoried in `assets/engine-inventory.md`; read them as reference, not as a test to pass.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The API client can list the deck and read study settings, through the same request path as comics, so an Access refusal, a 404 and an outage are classified as they already are
- [ ] The queue offers cards in the spec's order: learning and relearning due now, then other cards due now, then new cards in collection order while the day's allowance has room, then learning cards coming due within twenty minutes; longest-waiting first within a group
- [ ] The card just asked is skipped when another candidate exists, and a one-card deck still offers its card
- [ ] The day's allowance is the setting minus the cards introduced today, where today is the browser's local calendar day — not the UTC day
- [ ] An empty queue says whether the deck is empty or the day is done
- [ ] Remaining is zero exactly when the queue has nothing to offer
- [ ] The clock is passed into the queue, never read inside it
- [ ] `/practice` shows due, new and in-learning counts that add up to remaining, a start control, and a way to settings (both may lead nowhere yet)
- [ ] An empty deck and a finished day each show their own message
- [ ] A failed load of the deck or the settings shows an error with a retry, never default settings
- [ ] Unit tests cover the queue rules above and the new client calls
- [ ] Hand-off: a list for the developer to compare the three numbers against the phone, including after midnight local time
