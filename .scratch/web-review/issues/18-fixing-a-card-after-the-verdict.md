# 18 — Fixing a card after the verdict

**What to build:** From the feedback screen the reader can put a card right: change its translation, change whether it is a word or a sentence, reset it to new, or delete it. The actions wait until the answer just given is saved, and the rest of the session reflects the fix straight away. The card's source text cannot be changed, and the answer just given is not taken back.

See the spec's *Fixing a card*.

**Blocked by:** 12 — A translate session that saves.

**Status:** done (2026-10-12) — merged in #115; the browser checklist below is still the developer's to run

- [x] The API client can update a card's translation and kind, reset a card, and delete a card
- [x] The four actions appear on the feedback screen only, and are disabled until the review is saved
- [x] Changing the translation keeps the card where its schedule put it; it shows the new wording next time
- [x] Changing the kind updates the held deck, so later questions are built from it as it now stands
- [x] Reset returns the card as new, under the day's allowance
- [x] Delete asks for confirmation, then removes the card from the held deck and the session
- [x] The held deck is updated from each response, with no full fetch
- [x] An action that fails is reported and leaves the card as it was; a 404 treats the card as already gone
- [x] There is no control for the source text and none for undoing the answer
- [x] The actions are reachable from the keyboard
- [x] Unit tests cover the deck and session after each action, and the client calls
- [x] The `PATCH` and `DELETE` are confirmed once through the dev proxy against the real backend
- [x] Hand-off: a list for the developer covering each action and what the rest of the session does after it, on a narrow and a wide window

## Comments

Implemented 2026-10-12. 274 unit tests pass; the type check and production build are clean. The page was not opened in a browser, and **no real card was changed, reset or deleted**.

**The `PATCH`, `DELETE` and reset through the dev proxy** were confirmed with requests that cannot change anything: a `PATCH` with an empty body came back as the API's own 422 (*Provide translation, kind, or both*), and a `DELETE` and a reset of a card id that does not exist each came back as its 404 (*Learning card not found*). The deck was read before and after — 249 cards, identical.

The actions sit behind 修正這張卡片 under the verdict. It is disabled, not hidden, until the answer is saved. Delete takes two presses: 刪除卡片, then 確定刪除？無法復原. Reset does not ask — the ticket asks for confirmation on delete only — and it is the one to be careful with for that reason.

After a reset or a delete nothing more can be done to that card from the screen. A reset or deleted card stops counting toward 畢業 on the closing screen; the answer that was given stays counted.

A card with no kind shows neither 單字 nor 句子 selected. Clearing a kind back to none is something the backend allows and this screen does not offer.

**For the developer to check in the browser.** Every action here changes the real deck. Pick cards you do not mind changing.

- Under the verdict, 修正這張卡片 is greyed out for the instant the answer is saving, then usable.
- Open it: the translation field holds the card's current translation; the card's kind is highlighted.
- Change the translation and press Enter (with the Chinese input method on, the Enter that picks a candidate must not save): 譯文已更新, and the question's meaning above changes. The phone shows the new translation, and the card's schedule is as the answer left it.
- Switch 單字 / 句子: 類型已更新. A card turned from a sentence into a word is never again asked as a fill-in.
- 重設為新卡: the message says it is new again; the phone shows it as new; if today's allowance has room it comes back later in the session.
- 刪除卡片 once: it turns red and asks. 取消 backs out. Pressing it again deletes: the card is gone from the phone and is not asked again.
- After a reset or a delete, the panel is gone for that card and 下一題 still works.
- The whole panel can be worked with Tab, Enter and Space alone.
- Stop the backend and try an action: a message says the card was not changed, and it was not.
- A narrow window: the translation field and its button stay on one line, and the buttons wrap rather than overflow.
