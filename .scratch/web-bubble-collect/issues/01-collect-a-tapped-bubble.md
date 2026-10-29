# 01 — Collect a tapped bubble

**What to build:** The bubble translation card in the web reader gains a 加入句子 button. Pressing it closes the card and opens the collecting panel filled with the bubble's original text (upper-cased) and its translation, with the page fixed to the bubble's page. The reader edits as they like and adds with the panel's existing buttons. See [the spec](../spec.md).

This is the whole feature in one thin path: the pure upper-case function, the collecting store's fill action, the button on the card, and the reader view connecting them.

**Blocked by:** None — can start immediately.

**Status:** in review (2026-10-29) — PR open; device checklist pending with the developer

**Acceptance criteria**

- [x] The translation card shows a 加入句子 button, including for a bubble with no translation
- [x] Pressing it closes the card and opens the collecting panel
- [x] 原文 holds the bubble's original in upper case (mixed-case lines converted; Vietnamese diacritics and `đ` → `Đ` correct); 譯文 holds the translation, or is empty when there is none
- [x] The panel shows the bubble's page number, even when the reader's current page is a different one
- [x] Text already typed into the panel is replaced, with no prompt
- [x] The translation card still shows the original in OCR casing
- [ ] Adding, the already-collected notice, a failed save and the 已加入 confirmation behave as for a typed card
- [x] Unit tests cover the fill action and the upper-case function (see the spec's *Testing Decisions*); the web suite and `vue-tsc` pass

**Developer device checklist (handed over, not automated)**

- Tap a bubble → 加入句子 → the panel opens filled, the card is gone
- Phone width: the panel along the bottom does not hide the fields behind the keyboard in a way that blocks editing
- Wide window: the panel docks beside the page
- A bubble on a page boundary records its own page
- Add as 句子 and as 單字; the card appears in 字卡庫
