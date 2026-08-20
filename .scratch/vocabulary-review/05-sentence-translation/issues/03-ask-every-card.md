# 03 — Ask every card, at a difficulty that fits

**What to build:** Sentence translation joins the round, difficulty follows the ladder rung, and **word cards become askable**.

## The gap this closes

Of twenty-two word cards, **eleven appear in no sentence card**, so no cloze can be built from them:

```
BÓNG DÁNG   NGUYÊN TẮC   ÁP DỤNG    XÂM PHẠM    THẨM QUYỀN   Kiềm CHẾ
BẤT CẬP     PHÁ HUỶ      BỊ LÔI RA  QUỐC HỘI    NGUY
```

They are collected, listed, and counted on the practice card — and never practised. Generation was going to solve it and is parked; **a word card asked to be translated needs nothing generated**, so this closes the gap as a side effect.

## Difficulty follows the rung, not the day

| Ladder rung | What is asked |
|---|---|
| 0–1 | Cloze, four choices — recognition |
| 2–3 | Cloze typed, or a rearrangement — production with support |
| 4 | Sentence translation, typed — production from nothing |

**The rung, not the day.** Using the day would mean every card starts each morning at four-choice, including words learned months ago, and would make a card's two appearances in one round differ in difficulty — the second harder purely because the first went well.

**Stage 3's alternation goes**, in cloze as well. It was a placeholder for exactly this, put in because nothing then knew how familiar a card was.

**The whole deck sits on rung 0 today, so every question will be four-choice until cards start climbing.** That is correct rather than a defect, and worth expecting during the device pass.

**A card falls back to a type it can support.** A word card has no cloze; a sentence with no deck word in it has none either. Question types follow from what a card supports, as they have since stage 3.

**Blocked by:** 02.

**Status:** not started.

- [ ] A sentence card at the top rung is asked to be translated, typed
- [ ] A word card is asked to be translated at any rung it reaches, typed
- [ ] **All eleven orphaned word cards are askable** — asserted against the real deck's shape
- [ ] Each rung asks what the table says, and the day's step changes nothing about which type appears
- [ ] A card's two appearances in one round are the same difficulty
- [ ] A word card never gets a cloze, at any rung
- [ ] A sentence with no deck word in it falls back rather than producing nothing
- [ ] Every question type records its own `questionType`, so what was asked is recoverable later
- [ ] Sentence translation moves the ladder, exactly as cloze does
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
