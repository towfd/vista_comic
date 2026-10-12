# 16 — How a session ends

**What to build:** A session finishes properly. When the queue comes up empty the deck is checked once more before the reader is told they are done; then a closing screen reports how many answers were right and wrong and how many cards graduated. A session can also be stopped part-way.

See the spec's *The session's edges*.

**Blocked by:** 12 — A translate session that saves.

**Status:** ready-for-agent

- [ ] When the queue is empty, the deck is fetched once more and the queue asked again; the session ends only if it is still empty
- [ ] If that fetch fails, the session ends on what it holds rather than hanging
- [ ] The closing screen shows the session's correct and wrong counts and the number of cards that graduated, and leads back to the overview
- [ ] A card counts as graduated when its state after an answer is review, and stops counting if a later answer in the same session takes it out again
- [ ] A session with no answers given goes to the overview's own empty state, not a closing screen of zeros
- [ ] A stop control during a session returns to the overview; answers already saved stay saved
- [ ] After a finished session the overview says the day is done and the bar's count is gone or zero
- [ ] Unit tests cover the recheck and the outcome's counting
- [ ] Hand-off: a list for the developer covering a full session's closing numbers and collecting a card on the phone just before the last answer
