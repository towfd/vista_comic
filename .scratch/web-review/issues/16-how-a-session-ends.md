# 16 — How a session ends

**What to build:** A session finishes properly. When the queue comes up empty the deck is checked once more before the reader is told they are done; then a closing screen reports how many answers were right and wrong and how many cards graduated. A session can also be stopped part-way.

See the spec's *The session's edges*.

**Blocked by:** 12 — A translate session that saves.

**Status:** done (2026-10-12) — merged in #113; the browser checklist below is still the developer's to run

- [x] When the queue is empty, the deck is fetched once more and the queue asked again; the session ends only if it is still empty
- [x] If that fetch fails, the session ends on what it holds rather than hanging
- [x] The closing screen shows the session's correct and wrong counts and the number of cards that graduated, and leads back to the overview
- [x] A card counts as graduated when its state after an answer is review, and stops counting if a later answer in the same session takes it out again
- [x] A session with no answers given goes to the overview's own empty state, not a closing screen of zeros
- [x] A stop control during a session returns to the overview; answers already saved stay saved
- [x] After a finished session the overview says the day is done and the bar's count is gone or zero
- [x] Unit tests cover the recheck and the outcome's counting
- [x] Hand-off: a list for the developer covering a full session's closing numbers and collecting a card on the phone just before the last answer

## Comments

Implemented 2026-10-12. 240 unit tests pass; the type check and production build are clean. The page was not opened in a browser.

Two readings of the ticket worth stating:

- **Only saved answers are counted.** An answer the server never took, and one given for a card that turned out to be deleted, are not part of what the session achieved.
- **畢業 follows the phone's definition**, which is broader than the word suggests: a card counts when it stands in review after its last answer this session. A review card answered correctly counts, not only a learning card that cleared its last step. The closing screen says this in a line under the numbers.

結束 is a link back to the overview. It does not ask for confirmation: every earlier answer is already saved, and the answer on screen keeps saving in the background if it was submitted.

**For the developer to check in the browser:**

- Answer the last card: a brief 確認還有沒有卡片…, then 這一輪做完了 with 答對, 答錯 and 畢業. The network panel shows one `/cards` just before it.
- The three numbers match what you did: right and wrong add up to the answers given.
- Miss a card that had graduated earlier in the same session: 畢業 goes back down by one.
- Enter on the closing screen follows 回到總覽, which then says 今天做完了, and 練習 has no number.
- Just before the last answer, collect a card on the phone (with allowance left): after the last answer the session carries on with it instead of ending.
- Press 結束 mid-session: the overview shows what is left, and the cards already answered have moved on the phone.
- Open `/practice/session` directly when nothing is waiting: it goes to the overview, not to a screen of zeros.
