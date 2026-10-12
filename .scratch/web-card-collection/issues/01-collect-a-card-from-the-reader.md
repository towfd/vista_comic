# 01 — Collect a card from the reader

**What to build:** The reader gains a collect button in its header. Pressing it opens a panel docked to the right of the page column, with the manga still in view and still scrollable behind it. The reader types the source text and its translation, presses 加入單字 or 加入句子, and the card joins the real deck with the comic, chapter and page it came from. The panel then clears and collapses, and a short confirmation naming the line appears beside the button. The new card is in 字卡庫 and in the practice counts without a reload.

This is the whole path, thin: the API call, a collecting store that owns everything the panel does, the deck store taking the card in, and the panel itself. See [the spec](../spec.md) — *Implementation Decisions* for the store's rules and *Testing Decisions* for the seams.

Carried by this ticket, not left for later:

- **The page is fixed when the source field goes from empty to non-empty**, shown in the panel, held while the reader scrolls, and released when the field empties again, on a successful add, and on collapse.
- **Collapse is a full reset.** Nothing typed survives it; nothing is written to browser storage. Leaving the chapter is a collapse.
- **Both add buttons stay unavailable** until each field has real content, the source text is within the deck's 200-character limit, and a page is fixed — and while a card is being saved.
- **The target language is fixed** to the identifier the phone sends for Traditional Chinese, and a kind is always sent.
- **Typing in the panel is not scrolling.** Key presses from its fields do not reach the reader's scroll-input listener. Enter never submits.

Deliberately basic here, finished in ticket 02: when the line is already in the deck, or the save fails, this ticket shows a single plain message and keeps the panel open with the text intact. It must not collapse or confirm as though a new card was made.

Layout in this ticket is the wide-window one only; the narrow-window dock is ticket 03.

**Blocked by:** None — can start immediately.

**Status:** merged (2026-10-12) in #119 — browser checks are with the developer

- [ ] A collect button is present in the reader once a chapter's pages are shown, and the panel is collapsed by default
- [ ] Pressing the button opens the panel to the right of the page column with the cursor in the source field; the page column does not move or resize
- [ ] The manga scrolls behind the open panel
- [ ] Both fields start empty; the source field is marked as Vietnamese text
- [ ] The source field stops at 200 characters and shows the count as the limit nears
- [ ] The panel shows the page it has fixed; that page does not change when the reader scrolls after starting to type
- [ ] Emptying the source field releases the page, so typing again on another page records the new one
- [ ] 加入單字 and 加入句子 are unavailable while either field is empty or whitespace-only, and while a save is in flight
- [ ] Adding sends the source text, translation, kind, comic, chapter and fixed page, with the fixed target language
- [ ] On a new card: the fields clear, the panel collapses, and a confirmation naming the line appears by the button and goes away by itself
- [ ] The new card appears in 字卡庫 and in the practice overview's counts without a reload, and is not removed by a deck load that began before it was collected
- [ ] Collapsing by hand discards the fields and the fixed page; reopening is empty
- [ ] Changing chapter collapses the panel and discards its contents
- [ ] A space typed in either field neither scrolls the page nor opens the progress gate; Enter does not submit
- [ ] A line already in the deck, and a failed save, each show a message and leave the panel open with the text kept
- [ ] Unit tests cover the collecting store, the API client's card creation, and the deck store's new action, at the seams the spec names; the existing web suite still passes
- [ ] The developer is handed the browser checklist for what unit tests cannot cover
