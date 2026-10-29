# 04 — Collect a word

**What to build:** Each word in the analysis panel gets an 加入 button that opens 收卡 on top of the panel, filled with the word (upper case) and `meaning（hanViet）` or `meaning`, recorded on the bubble's page, through the collecting store's existing `fillFromBubble`. Closing 收卡 or adding a card leaves the analysis panel as it was. See [the spec](../spec.md).

**Blocked by:** 03

**Status:** done (2026-10-29) — on `feature/web-line-analysis`; device checks pending

**Notes from implementation**

- The fill text is `wordTranslation` in `stores/analysis.ts` (tested there); the word goes through `fillFromBubble`, so it is upper-cased by the same rule as a bubble line.
- The analysis panel's visibility depends only on its own store, so 收卡 opening or closing never remounts it — its scroll position stays.

**Acceptance criteria**

- [x] 加入 opens 收卡 above the analysis panel with the word and its meaning text as specified
- [x] Adding a card or collapsing 收卡 reveals the analysis panel at the same scroll position
- [x] Unit tests cover the fill text; the web suite and `vue-tsc` pass

**Developer device checklist**

- Collect three words from one line in a row, as 單字
- Phone width: 收卡 over the analysis panel is usable with the keyboard up
