# 10 — Today's deck on the overview

**What to build:** Opening `/practice` shows what is waiting today — how many cards are due, new, and in learning — worked out in the browser from the deck and settings the phone already uses. Nothing is written: this is the read-only foundation, and its numbers can be checked against the phone before any answer is ever posted. It brings the web's first calls about cards, the queue rules, and the store that holds the deck.

See the spec's *The queue* and *When the deck is fetched*. The phone's queue rules are inventoried in `assets/engine-inventory.md`; read them as reference, not as a test to pass.

**Blocked by:** None — can start immediately.

**Status:** done (2026-10-12) — merged in #107; the browser checklist below is still the developer's to run

- [x] The API client can list the deck and read study settings, through the same request path as comics, so an Access refusal, a 404 and an outage are classified as they already are
- [x] The queue offers cards in the spec's order: learning and relearning due now, then other cards due now, then new cards in collection order while the day's allowance has room, then learning cards coming due within twenty minutes; longest-waiting first within a group
- [x] The card just asked is skipped when another candidate exists, and a one-card deck still offers its card
- [x] The day's allowance is the setting minus the cards introduced today, where today is the browser's local calendar day — not the UTC day
- [x] An empty queue says whether the deck is empty or the day is done
- [x] Remaining is zero exactly when the queue has nothing to offer
- [x] The clock is passed into the queue, never read inside it
- [x] `/practice` shows due, new and in-learning counts that add up to remaining, a start control, and a way to settings (both may lead nowhere yet)
- [x] An empty deck and a finished day each show their own message
- [x] A failed load of the deck or the settings shows an error with a retry, never default settings
- [x] Unit tests cover the queue rules above and the new client calls
- [x] Hand-off: a list for the developer to compare the three numbers against the phone, including after midnight local time

## Comments

Implemented 2026-10-12. 114 unit tests pass, the type check and production build are clean, and `GET /cards` and `GET /study/settings` were read once through the dev proxy against the real backend (249 cards; settings `[5, 7, 10]` / `15`). The dev proxy gained `/cards` and `/study`.

The start and settings controls are rendered disabled; tickets 12 and 17 enable them. The overview carries a plain link back to the library until ticket 11 adds the navigation bar.

**For the developer to check in the browser** (`npm run dev`, then `localhost:5173/practice`):

- The page shows three numbers — 到期, 新卡, 學習中 — or one of the two messages below, never both.
- Open 練習 on the phone at the same moment: the phone's count of what is left equals the three numbers added together.
- 到期 counts only cards in review that are due now; a card the phone shows as "Learning" or "Relearning" and due within twenty minutes is under 學習中, not 到期.
- With no uncollected new cards, 新卡 is 0. After collecting one on the phone and reloading, it is 1 — unless today's allowance is already spent, in which case it stays 0.
- Finish everything on the phone, reload: the page says 今天做完了 and shows no numbers.
- Shortly after local midnight (before 08:00), 新卡 reflects a fresh day's allowance, matching the phone.
- Stop the backend, or break the token in `web/.env` and restart the dev server: the page shows the error with 重試, never a row of zeros. Restore it and press 重試: the numbers appear.
- In the network panel, the page makes exactly two requests about cards — `/cards` and `/study/settings` — both to `localhost:5173`.
- One narrow window (about 375 wide) and one wide: the three boxes stay on one row and nothing overflows.
- The library, a comic page and the reader behave as before.

Not checkable here: the empty-deck message, since the real deck is not empty. It is covered by the queue's unit tests only.
