# 19 — The card library

**What to build:** Fixing a card moves out of the practice session and into a page of its own, 字卡庫. The page lists every card under 單字 and 句子 with counts, can be searched by its text or its meaning, and shows where each card stands in the schedule. Opening a card gives the four fixing actions — change the translation, change the kind, reset, delete. The panel under the verdict in a session is replaced by a link that opens that card in the library in a new tab.

This is asked for by the developer on 2026-10-12, after using ticket 18's panel: it reverses the spec's *"The card library screens — out of scope"* and supersedes the map's [Fixing a card mid-practice](09-fixing-a-card-mid-practice.md) as to *where* a card is fixed. It is part ⑤ of [the web client's split](../../web-client/issues/09-the-six-part-split.md), taken early and thin: the card's source page, its lookup count, and a link back to the reader are not in it.

Decisions, each put to the developer:

- **The session keeps a link, not a panel.** Under the verdict, once the answer is saved, a link opens the card in the library in a new tab. One screen fixes cards; a session is not interrupted; coming back to the session's tab refetches the deck, so a fix applies from the next question.
- **In the first version:** search, the 單字 / 句子 grouping, and the schedule state. Not in it: where a card was collected and how often it was looked up.

Filled in by the agent, not put as choices:

- **The route is `/deck`, not `/cards`** — the dev proxy forwards `/cards` to the backend, so a page at that path could not be opened or reloaded. A card is `/deck/:cardId`.
- A card with no kind is listed under a third heading, 未分類, shown only when there is one.
- **Reset asks for confirmation as delete does.** Ticket 18 confirmed delete only; with a page of its own there is room to ask, and a reset discards a card's whole history.
- The source text is still not editable, and a review is still not undone.

**Blocked by:** 18 — Fixing a card after the verdict.

**Status:** done (2026-10-12) — merged in #116

- [x] The navigation bar gains 字卡庫, between 書庫 and 練習, current on the library's pages
- [x] The library lists every card under 單字 and 句子, each heading with its count and able to fold; cards with no kind appear under 未分類 only when there are any
- [x] A search field narrows the list by source text or translation, ignoring case and spacing; the counts follow; no match says so
- [x] Each row shows the card's text, its translation and where it stands: new, learning or relearning with its step, or its interval in days — and when it is next due
- [x] A failed load shows an error with a retry
- [x] A card's own page shows the same, and offers: change the translation, change the kind, reset, delete
- [x] Reset and delete each ask for confirmation; after a delete the page returns to the list
- [x] A change is reported, held in the deck store, and shows in the list and in the count beside 練習 without a reload
- [x] A failed action is reported and leaves the card as it was; a card the server no longer has is treated as deleted
- [x] A card id that is not in the deck shows a not-found state with a way back to the list
- [x] The session's feedback screen offers a link to the card in the library, opening in a new tab, once the answer is saved — and no fixing panel
- [x] The session store no longer carries fixing state or actions
- [x] Unit tests cover grouping, search, the schedule wording and the deck store's fixing actions
- [x] Hand-off: a list for the developer to check in a browser

## Comments

Implemented 2026-10-12. 286 unit tests pass; the type check and production build are clean. The pages were not opened in a browser, and no real card was changed.

The fixing actions moved from the session store to the deck store, where the library and anything later can reach them; the session store is back to asking, judging and saving. Ticket 18's panel component is deleted.

One thing lost with the panel: a card reset or deleted in the library still counts toward 畢業 on that session's closing screen if it had graduated there, since the session no longer hears about it.

Due dates are worded here, not by the browser: 已到期, N 分鐘後, N 小時後, N 天後.

**For the developer to check in the browser.** Every action on a card's page changes the real deck.

- 字卡庫 is in the bar between 書庫 and 練習, and is the bright entry on `/deck` and on a card's page.
- `/deck` lists every card under 單字 and 句子 with counts that add up to 共 N 張. Each heading folds and unfolds, by click and by keyboard.
- Each row shows the text, the translation, and a line like 間隔 7 天 · 3 天後, 學習中 2/3 · 4 分鐘後, or 已到期 — matching what the phone's card detail says.
- Type part of a word in the search field, in lower case, for a card stored in capitals: it is found, and the counts shrink. Type part of a translation: found. Type nonsense: 沒有符合 … 的卡片.
- Click a card: its page shows the text, where it stands, the translation in a field, and its kind highlighted.
- Change the translation and press Enter (with the Chinese input method on, the Enter that picks a candidate must not save): 譯文已更新。 Go back to the list: the row shows it. The phone shows it.
- Switch 單字 / 句子: 類型已更新, and in the list the card has moved to the other heading.
- 重設為新卡 once: it turns amber and asks. 取消 backs out. Again: the card reads 新卡, and the count beside 練習 changes. It is disabled for a card that is already new.
- 刪除卡片 once: red, asks. Again: back on the list, the card is gone, and gone from the phone.
- Open `/deck/999999999`: 找不到這張卡片, with a way back.
- Reload on `/deck` and on a card's page: the same page comes back, not JSON.
- In a session, after a verdict: a line 這張卡片有問題？到字卡庫修改 ↗ under 下一題, and no panel. It opens that card in a new tab. Fix the translation there, switch back to the session: the network panel shows `/cards` refetched, and the card carries the new translation the next time it is asked.
- Stop the backend and try an action on a card's page: a message says the card was not changed.
- A narrow window (about 375 wide): the bar's four entries fit on one line; long sentences in the list are cut at two lines; a card's page does not scroll sideways.
