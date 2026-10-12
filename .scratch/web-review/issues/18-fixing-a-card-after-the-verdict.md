# 18 — Fixing a card after the verdict

**What to build:** From the feedback screen the reader can put a card right: change its translation, change whether it is a word or a sentence, reset it to new, or delete it. The actions wait until the answer just given is saved, and the rest of the session reflects the fix straight away. The card's source text cannot be changed, and the answer just given is not taken back.

See the spec's *Fixing a card*.

**Blocked by:** 12 — A translate session that saves.

**Status:** ready-for-agent

- [ ] The API client can update a card's translation and kind, reset a card, and delete a card
- [ ] The four actions appear on the feedback screen only, and are disabled until the review is saved
- [ ] Changing the translation keeps the card where its schedule put it; it shows the new wording next time
- [ ] Changing the kind updates the held deck, so later questions are built from it as it now stands
- [ ] Reset returns the card as new, under the day's allowance
- [ ] Delete asks for confirmation, then removes the card from the held deck and the session
- [ ] The held deck is updated from each response, with no full fetch
- [ ] An action that fails is reported and leaves the card as it was; a 404 treats the card as already gone
- [ ] There is no control for the source text and none for undoing the answer
- [ ] The actions are reachable from the keyboard
- [ ] Unit tests cover the deck and session after each action, and the client calls
- [ ] The `PATCH` and `DELETE` are confirmed once through the dev proxy against the real backend
- [ ] Hand-off: a list for the developer covering each action and what the rest of the session does after it, on a narrow and a wide window
