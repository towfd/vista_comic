Status: ready-for-agent

# 08 — What a card says about itself

**What to build:** The readouts in 單字庫 and the card detail screen, and the removal of the
adjectives.

A row reads `新卡`, `學習中 2/3 · 7 分鐘後`, `21 天 · 3 天後到期`, or `重新學習 1/3`. The detail
screen shows the same plus the slot as `n / 7`.

`Familiarity` is deleted. It was an alias for the rung, which is why a screen full of
`Familiarity New` was what provoked this rewrite — the word looked like a verdict on the reader
while describing a column that had not moved. What replaces it says only what the system knows.

Also in this ticket: **revise the PRD.** The lesson architecture, the two-clocks section, 錯題區,
the weighting rule for selection, the stage list and the spec table all describe a model this
stage replaces, and line 313's claim that judging requires tones has been false since `551c42c`.

**Blocked by:** 04.

- [ ] Every state renders on a row, including a relearning card
- [ ] Minutes, days and dates are formatted for the reader's locale
- [ ] The detail screen agrees with the row
- [ ] `Familiarity` and its tests are gone
- [ ] The PRD no longer describes the three-step day, 錯題區, 翻牌 or the once-a-day ladder
- [ ] Both phone layouts, and long source text does not push the readout off the row
