# 20 — Acting on history records

**What to build:** The reader can do something about what they find in 歷史紀錄, not just look at it: retry an explanation that failed, jump back to the page a record came from, swipe records away, and understand what they are seeing when the list is empty or the server is unreachable.

**Retry lives only on the detail screen.** Reaching it requires a deliberate tap into one record, which is precisely how it stays hard to trigger by accident from a list of many rows. A `declined` record offers no retry at all — retrying would spend quota to receive the same verdict.

Deletion moves from a button to a **swipe**, because every translate now writes a row and pruning becomes a routine act rather than a rare one. The confirmation stays: deletion is still irreversible and there is no undo.

Empty and unreachable must read as different things. This is not polish — the existing store convention already forbids degrading a read failure into an empty list, because that misrepresents "the store is unreachable" as "you have nothing". The empty copy also changes in kind from 單字本's: the reader never chose to save anything, so an empty history is a statement about the feature, not about their diligence.

**Blocked by:** 19 (the tab and detail screen it acts on).

**Status:** ready-for-agent

- [ ] A `failed` record's detail offers retry, which returns it to being produced; a `declined` record offers none.
- [ ] Retry is reachable only from the detail screen, never from a list row.
- [ ] Swiping a row deletes it, behind the existing confirmation; the detail screen also offers delete.
- [ ] A deleted record disappears from the list without a full reload.
- [ ] Jump-back to the source page survives from 單字本, unchanged: it opens the exact page read-only, without moving real reading progress.
- [ ] Jump-back is **disabled** for a record whose comic has left the library, since that navigation would fail — and such a record is still readable.
- [ ] The empty state explains what will appear there, in terms of automatic recording rather than saving.
- [ ] An unreachable backend shows a distinct message with a retry, never an empty list.
- [ ] XCUITest code for retry, delete and jump-back is written and build-verified; running it is handed off.
