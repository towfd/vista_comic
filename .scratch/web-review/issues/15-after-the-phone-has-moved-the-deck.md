# 15 — After the phone has moved the deck

**What to build:** The web notices what was done on the phone when the reader comes back to the tab. The deck is fetched again when the tab becomes visible; a question already on screen is left alone and can still be answered; the fresh deck takes effect from the next question. A tab left open overnight needs no reload.

See the spec's *When the deck is fetched*.

**Blocked by:** 12 — A translate session that saves.

**Status:** done (2026-10-12) — merged; the browser checklist below is still the developer's to run

- [x] The deck and settings are fetched again when the tab becomes visible, on the overview and during a session
- [x] A question on screen is never replaced or cleared by a fetch, and what has been typed stays
- [x] The next question is computed from the refreshed deck
- [x] A fetch that fails here is dropped quietly and the held deck kept
- [x] A response to a review arriving after a fetch does not overwrite newer data for other cards, and a fetch does not undo a review response for the card just answered
- [x] The clock and the local day are taken fresh for each question, so a session resumed after midnight sees the new day's allowance
- [x] Unit tests cover the session store across a refetch
- [x] Hand-off: a list for the developer covering answering on the phone then returning to the tab, both on the overview and mid-question

## Comments

Implemented 2026-10-12. 230 unit tests pass; the type check and production build are clean. The page was not opened in a browser.

The listener lives in the navigation bar, so it covers every page that shows anything about cards — the library's count included — and is absent in the reader. The refresh is quiet both ways: no loading state, and a failure keeps the deck already held.

**How a fetch and an answer are kept from undoing each other.** A fetch reports the deck as the server held it when it answered. If this tab saved an answer for a card after that fetch set out, the tab's copy of that card is the newer one and is kept; every other card takes the server's word. The same goes for a card removed here meanwhile. Without this, a fetch that crossed with a save would put the card back as due and it would be asked twice.

**For the developer to check in the browser:**

- On the overview, answer a few cards on the phone, then switch back to the tab: the three numbers and the count beside 練習 drop without a reload, and the network panel shows one `/cards` and one `/study/settings`.
- With a question on screen and half an answer typed, answer that same card on the phone and switch back: the question and what you typed are still there. Finish it; the next question is a different card.
- Collect a new card on the phone mid-session and switch back: it turns up later in the session if today's allowance has room.
- Switch away and back with the backend stopped: nothing changes on screen and no error appears.
- Leave a session open past midnight and answer the next question in the morning: new cards are offered again.
- Switching back to the tab while reading manga makes no request about cards.
