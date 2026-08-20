# 02 — Build a cloze question from a card

**What to build:** The rule that turns a card into a question, or decides it cannot.

A card carries a cloze when it is a **sentence** and at least one deck word occurs in it. The blank is one of those words; four choices come from the reader's other cards.

**Which word gets blanked: the least familiar one present.** That is the one worth testing, and it reuses familiarity the deck already tracks rather than inventing a second idea of what needs practice.

**A card that cannot carry a cloze produces nothing, and the round moves on.** Question types follow from what a card actually supports — never from blanking something arbitrary to fill a slot. With a small deck this will be common and it is not an error state. A **word** card produces no cloze at all in this stage: it has no sentence to blank, and generating one is stage 6.

**Distractors are the reader's own cards**, so no dictionary and no generation is involved — and they are revision in their own right, since choosing correctly means reading all four. Fewer than four cards means no four-choice question can be built.

**Blocked by:** 01.

**Status:** implemented on branch `feat/cloze-round`, 2026-08-20. Pure functions; nothing user-visible.

- [x] A sentence card containing a deck word produces a cloze whose blank is that word
- [x] Where several deck words occur, the least familiar is blanked
- [x] A sentence card containing no deck word produces no question
- [x] A word card produces no question
- [x] Distractors are other cards, never the answer, and never repeated inside one question
- [x] Fewer than four cards produces no four-choice question
- [x] A typed answer is judged after the same normalisation: punctuation and spacing are ignored, spelling and tones are not
- [x] A typed answer with a changed tone is wrong
- [x] Question building is pure — cards in, questions out, no repository

## What was built

`Features/Study/ClozeQuestion.swift` — `makeCloze(from:deck:)`, `distractors(for:from:count:)` and
`isCorrectClozeAnswer(_:for:)`.

**Three guards came from looking at the real deck rather than from imagining edge cases:**

1. **A blank must leave something to read**, and getting this right took two attempts. The first
   rule excluded the card itself — and the test written from the real deck failed, because the
   deck holds three *near-identical* copies of one sentence, so a **different** card still matched
   the whole thing and produced a question that was nothing but a blank. The rule is therefore
   about what the blank covers, not about which row it came from: a match spanning the sentence is
   discarded whoever owns it.

   Worth recording because a fixture would never have caught it. One sentence card and a few
   unrelated words — the obvious test data — passes happily, and the defect would have surfaced on
   the device as a question showing a single underscore.
2. **A distractor equal to the answer after normalisation is refused.** The deck holds cards
   differing only in spacing and case; offered as an option, the question would have two right
   answers.
3. **Ties break on position.** Every card sits on rung 0 until stage 4, so *everything* ties on
   familiarity — without a second key the blank would move between runs and no test could state
   where it lands.

## Verification

17 tests: which word is removed and why, every reason a card produces no question (word card,
unclassified card, no deck word, self-match), distractor selection, and typed judging — where a
changed tone is wrong, and an empty answer is wrong rather than vacuously right.
