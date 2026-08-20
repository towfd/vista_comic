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

**Status:** implemented on branch `feat/sentence-translation`, 2026-08-20. **Awaiting the repo owner's device pass.**

- [x] A sentence card at the top rung is asked to be translated, typed
- [x] A word card is asked to be translated at any rung it reaches, typed
- [x] **All eleven orphaned word cards are askable** — asserted against the real deck's shape
- [x] Each rung asks what the table says, and the day's step changes nothing about which type appears
- [x] A card's two appearances in one round are the same difficulty
- [x] A word card never gets a cloze, at any rung
- [x] A sentence with no deck word in it falls back rather than producing nothing
- [x] Every question type records its own `questionType`, so what was asked is recoverable later
- [x] Sentence translation moves the ladder, exactly as cloze does
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

The round is now built from **cards** rather than from cloze questions. That one change is what
closes the gap: `deck.compactMap { makeCloze(...) }` silently dropped every card that could not
carry a blank, which was eleven of twenty-two word cards.

`askableModes(for:deck:)` asks the rung what difficulty to use, then asks the card what of that it
can actually do, and **falls back to whatever it can** rather than dropping it. Typed translation
always applies — it asks for the card itself — so a card is only ever excluded when there is no
text to ask for.

**Four tests changed rather than four bugs being fixed**, and the distinction is worth recording:

- Two asserted that a deck with no usable sentence can build no round. True while cloze was the
  only question type, and precisely the rule that left eleven cards unpractised. Now a deck of
  only words builds a round of translations.
- Two were mine and too narrow: a multi-word sentence with no deck word inside it can still be
  **rearranged**, so the fallback offers `[.rearranging, .translating]`. I had written the spec
  saying a card's two appearances use different modes, then written the test asserting they must
  be the same.

## Device checklist for the repo owner

**Every card sits on rung 0, so every sentence question will be four-choice.** That is the
difficulty curve working, not failing — rearranging needs rung 2, sentence translation rung 4.

1. Play a round. Sentences appear as four-choice cloze, as before.
2. **⭐ Word cards now appear**, showing the meaning and asking for the Vietnamese typed. The
   eleven that appear in no sentence — `QUỐC HỘI`, `BẤT CẬP`, `NGUYÊN TẮC` and the rest — are
   askable for the first time.
3. Type one with tones: correct. Type one without: correct, with **Watch the tones**.
4. **Type one with the full stop left off** (or added): still correct. This is the punctuation
   fix.
5. Type a word that is not the answer: wrong, and the answer is named.
6. The sentence in a question is now noticeably larger than before — it was rendering at
   list-row size.
7. Both phone sizes.
