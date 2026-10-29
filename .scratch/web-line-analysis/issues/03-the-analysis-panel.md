# 03 — The analysis panel

**What to build:** The web side up to reading a result: the 深入查詢 button on the translation card (bubbles with a translation only), the analysis panel with its model picker, the API client calls, an analysis store that polls and shows waiting / failed (with 重試) / done states, the word list, grammar and tone, and 重新查詢 with its cost reminder. Names are filtered from `bible.json` and sent with the request. See [the spec](../spec.md) — *The web side*.

**Blocked by:** 01 (the API contract)

**Status:** ready-for-agent

**Acceptance criteria**

- [ ] 深入查詢 shows only on bubbles with a translation; pressing it closes the card and opens the panel
- [ ] The picker offers Sonnet 5.5 / Opus 5.5 / Fable 5.1, defaults to Sonnet, and remembers the last choice (works without storage)
- [ ] While pending the panel shows the model and the elapsed time; closing it and reopening the bubble later finds the result
- [ ] Each failure reason has its own message and a 重試
- [ ] A done result lists every word (upper case, meaning, part of speech, characters when present, note when present), then grammar and tone
- [ ] Switching model shows a stored result or runs one; 重新查詢 asks first and replaces the result
- [ ] Vitest covers the store and the name filter; the web suite and `vue-tsc` pass

**Developer device checklist**

- Phone width and wide window: the panel's position, scrolling a long word list, the ＋收卡 button not covered
- A Fable run: the waiting state over a minute
- Close mid-run, reopen the bubble: the result is there
