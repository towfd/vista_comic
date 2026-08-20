# 02 — Rearrange a sentence

**What to build:** The scrambled-pieces question: the answer's own words, shuffled, to be put back in order.

No distractors. The question is whether the reader knows how the sentence goes, and ordering is where Vietnamese grammar lives.

**Split on spaces**, which for Vietnamese means splitting on *syllables* — `ĐẠO LUẬT` becomes two pieces even though it was collected as one word. Keeping deck words whole is the alternative and needs the deck as a word list; splitting has no dependency and one rule. **The deck's sentences are long, so expect twelve to fifteen pieces** — if that proves miserable on a device, keeping deck words whole is a change to one function rather than to the design.

**Only sentence cards.** Six word cards in the deck are a single syllable, so there would be one piece and nothing to arrange; most of the rest are two, where guessing is right half the time.

**Judge the assembled string, never the arrangement.** Two sentences in the deck repeat a word — `CÒN` and `MÌNH` in one, `LỢI` in another — so the screen shows identical pieces the reader cannot tell apart, and **both placements are correct**. Checking which tile went where would mark a right answer wrong.

**Blocked by:** 01.

**Status:** implemented on branch `feat/sentence-translation`, 2026-08-20 — covered by `RearrangementTests`. **Awaiting the repo owner's device pass.**

- [x] The pieces are exactly the answer's words, split on whitespace, and every one is offered
- [x] The shuffle never presents them already in order
- [x] Assembling them correctly is correct, judged through ticket 01's function
- [x] A sentence repeating a word offers two identical pieces, and **either placement is accepted** — asserted against the two real sentences that do this
- [x] A word card never produces a rearrangement
- [x] A sentence of one word produces none either
- [x] Pieces can be placed and taken back before answering
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

`sentencePieces`, `canRearrange`, `shuffledPieces`, `judgeArrangement`, and the tapping UI.

**The shuffle retries a bounded number of times rather than looping.** A sentence of two identical
words has no arrangement that differs from the original, and `while shuffled == original` would
hang the screen on it. The deck does not contain one yet — but `LỢI DỤNG … LỢI ÍCH` is close, and
a short sentence collected later could be exactly that.

**Judging compares the assembled string, never which tile went where.** Two of the deck's
sentences repeat a word — `CÒN` and `MÌNH` in one, `LỢI` in the other — so the screen shows
identical pieces the reader cannot tell apart, and both placements are correct.

Pieces wrap in a grid rather than scrolling in one row, since a sentence splits into twelve to
fifteen. **Take back** undoes one piece: a misplacement near the end of fifteen should not cost
the other fourteen.
