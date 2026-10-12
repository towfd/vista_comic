# 15 — After the phone has moved the deck

**What to build:** The web notices what was done on the phone when the reader comes back to the tab. The deck is fetched again when the tab becomes visible; a question already on screen is left alone and can still be answered; the fresh deck takes effect from the next question. A tab left open overnight needs no reload.

See the spec's *When the deck is fetched*.

**Blocked by:** 12 — A translate session that saves.

**Status:** ready-for-agent

- [ ] The deck and settings are fetched again when the tab becomes visible, on the overview and during a session
- [ ] A question on screen is never replaced or cleared by a fetch, and what has been typed stays
- [ ] The next question is computed from the refreshed deck
- [ ] A fetch that fails here is dropped quietly and the held deck kept
- [ ] A response to a review arriving after a fetch does not overwrite newer data for other cards, and a fetch does not undo a review response for the card just answered
- [ ] The clock and the local day are taken fresh for each question, so a session resumed after midnight sees the new day's allowance
- [ ] Unit tests cover the session store across a refetch
- [ ] Hand-off: a list for the developer covering answering on the phone then returning to the tab, both on the overview and mid-question
