Status: in progress — ticket 01

# Due forecast: how many cards fall due on which of the coming days

## Problem Statement

Raised by the owner on 2026-11-22, relayed by the main session: 「幫我在字卡的那個畫面幫我加上目前有幾張是哪幾天要到期的 例如 1天 3天 7天 21天這樣」.

Each card in 字卡庫 already says when it is next due (「3 天後」), and the practice overview says how many fall due tomorrow once the day is done. Nothing says how the deck spreads over the days ahead.

## Solution

A row of tiles, 今天 · 1 天 · 3 天 · 7 天 · 21 天 · 更久, each counting the cards that fall due then. It goes on 字卡庫, where pressing a tile narrows the list to those cards, and on the practice overview, where pressing a tile opens 字卡庫 narrowed.

Two throwaway preview pages were shown to the owner on the LAN before anything was built (scratchpad, not kept): the first compared the two readings below, the second showed the chosen one on both pages.

## Decisions

Made with the owner on 2026-11-22.

| Question | Decision | By |
|---|---|---|
| Which screen | The web's 字卡 tab (字卡庫, `/deck`). The phone's 單字庫 is not in this. | Main session's reading; the owner's later choices were all on the web previews |
| What 1 / 3 / 7 / 21 mean | **How many days until a card is due**, not which ladder rung it stands on. The numbers happen to be the first four rungs (`LADDER_INTERVALS`), so both were previewed; a card on 間隔 7 天 can be due tomorrow. | Owner |
| Separate tiles or a running total | **Separate:** each card is in one tile. 3 天 covers 2–3 days away, 7 天 4–7, 21 天 8–21. | Owner |
| Also on the practice overview | Yes. | Owner |
| The practice overview's tiles | 1 天 to 更久, no 今天: the page above already says what today holds, and a 今天 tile would not match it (the bubbles count new cards, and leave out what falls due later today). A line under the tiles names what falls due later today. | Main session, shown in the preview, approved |
| 明天到期 on the finished-day overview | Removed: the 1 天 tile is the same number. | Main session, shown in the preview, approved |
| Pressing a tile | 字卡庫: narrows the list (press again or 看全部 to undo). Overview: opens 字卡庫 narrowed. | Main session, shown in the preview, approved |
| 「今天做完了……明天再來」 when cards fall due later today | Left as it is: it predates this, and the owner did not ask to change it. | Owner (not raised) |

## Out of scope

- The phone app.
- Grouping by ladder rung.
- A chart over time.
