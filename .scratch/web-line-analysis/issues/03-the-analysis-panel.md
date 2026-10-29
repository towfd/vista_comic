# 03 — The analysis panel

**What to build:** The web side up to reading a result: the 深入查詢 button on the translation card (bubbles with a translation only), the analysis panel with its model picker, the API client calls, an analysis store that polls and shows waiting / failed (with 重試) / done states, the word list, grammar and tone, and 重新查詢 with its cost reminder. Names are filtered from `bible.json` and sent with the request. See [the spec](../spec.md) — *The web side*.

**Blocked by:** 01 (the API contract)

**Status:** done (2026-10-29) — on `feature/web-line-analysis`; device checks pending

**Notes from implementation**

- `/line-analyses` added to the dev proxy (`vite.config.ts`) and the nginx proxy (`nginx.conf.template`), or the requests would fall through to the app.
- A name matches as a whole word, ignoring case (`An` is not found in `Anh`); an alias match sends the entry's source name.
- 重新查詢's reminder is inline (確定／取消), not a browser dialog.
- The waiting clock counts from when the analysis was queued (`updatedAt`), so reopening mid-run shows the whole wait.
- Polling stops when the panel closes; a connection blip while polling is retried, a 404 is shown.

**Acceptance criteria**

- [x] 深入查詢 shows only on bubbles with a translation; pressing it closes the card and opens the panel
- [x] The picker offers Sonnet 5.5 / Opus 5.5 / Fable 5.1, defaults to Sonnet, and remembers the last choice (works without storage)
- [x] While pending the panel shows the model and the elapsed time; closing it and reopening the bubble later finds the result
- [x] Each failure reason has its own message and a 重試
- [x] A done result lists every word (upper case, meaning, part of speech, characters when present, note when present), then grammar and tone
- [x] Switching model shows a stored result or runs one; 重新查詢 asks first and replaces the result
- [x] Vitest covers the store and the name filter; the web suite and `vue-tsc` pass

**Developer device checklist**

- Phone width and wide window: the panel's position, scrolling a long word list, the ＋收卡 button not covered
- A Fable run: the waiting state over a minute
- Close mid-run, reopen the bubble: the result is there
