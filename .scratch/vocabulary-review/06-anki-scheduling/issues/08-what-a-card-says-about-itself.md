Status: implemented on branch `feat/anki-offline`, 2026-08-31

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

## What was built

`scheduleState` / `scheduleDue` / `scheduleSummary` in `CardSchedule.swift`, on
單字庫's rows, the card detail screen and the question header. `Familiarity` is
deleted.

**The row now says what the system knows.** `New`, `Learning 2/3 · in 7 min`,
`21 days · in 3 days`, `Relearning 1/3`. A graduated card is described by its
**interval** rather than its slot number: "21 days" is a fact about the reader's
memory, "slot 3" is a fact about an array.

A new card shows no due time. It waits on the day's quota rather than on a
clock, and "due now" beside it would be describing the wrong thing.

**33 strings were translated into 繁中** in the same pass, and the strings the
old model owned were removed from the catalog. New UI in English would have
shipped a half-translated app.

The PRD's *lesson architecture* section was rewritten rather than annotated: it
described a three-step day, a once-a-day ladder, 錯題區 and a weighting rule,
none of which exist. The settled-decisions table's rows for scheduling, question
types and offline were rewritten too, each saying what it used to say and why it
changed.
