# 03 — A round you can play

**What to build:** A **練習** tab holding a round of five cloze questions, answerable by choosing or by typing.

This is the first time the app asks the reader anything, and the first evidence about the question the whole PRD exists to answer: *will they come back?*

**Nothing is recorded.** No `card_review` rows, no ladder movement, no mistakes area. This round is deliberately a toy — it proves the questions are answerable and worth answering, and stage 4 is where results start to mean something. Building the recording first would mean recording results from a round nobody had tried.

For the same reason a wrong answer is simply shown as wrong and the round continues; the repeat-until-correct rule belongs with the three-step day in stage 4.

**Answer modes alternate.** Nothing yet knows how familiar a card is, so nothing can choose between four-choice and typed — alternating gets both interfaces exercised, and stage 4 replaces the alternation with the real difficulty ladder.

**A fourth tab: 書庫 / 已下載 / 練習 / 單字庫.** Practice is the point of the whole system, where 單字庫 is a workshop the reader should rarely need. Putting practice behind it would mean walking through the room nobody visits to reach the thing to do daily.

**Blocked by:** 02.

**Status:** implemented on branch `feat/cloze-round`, 2026-08-20. **Awaiting the repo owner's device pass** (checklist below).

- [x] A 練習 tab exists; the tab bar has four tabs
- [x] A round presents five questions and ends when all five are answered
- [x] Both answer modes appear across a round
- [x] A correct answer is confirmed; a wrong one shows what the answer was and the round continues
- [x] A deck too small to build a round says how many more words are needed, rather than showing a broken round
- [x] A deck with no sentence cards says so distinctly — nothing is wrong, there is simply nothing to blank yet
- [x] Leaving mid-round and returning does not resume a half-finished round; it starts a new one, since nothing is being recorded
- [x] Nothing is written to the backend by playing
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `Features/Study/PracticeRound.swift` — the round as a value: `makeRound(from:)`, `PracticeItem`,
  `RoundUnavailable`, `RoundOutcome`.
- `Features/Study/PracticeView.swift` — the tab, the round, and the summary.
- `RootTabView` — 練習 added before 單字庫; four tabs.

**Two decisions worth review:**

1. **"Not enough words" and "nothing to practise" are separate states with separate wording**, and
   both are worked out *before* the reader taps anything. It matters with this deck: 30 cards is
   plenty of words, so telling the reader to collect more when what they lack is a *sentence
   containing a word they already have* would send them to the wrong action.
2. **A short deck repeats cards rather than shortening the round.** Honest at this size — a
   shorter round would quietly hide how little there is to practise.

A question whose deck cannot supply four options is typed regardless of the alternation: showing
two options and calling it a choice would be worse than asking the reader to type.

## Verification

12 tests on the round. Two are worth naming:

- **An untouched round is not "all correct".** Zero wrong out of zero answered is easy to write as
  a perfect score, and the reader would open the tab to be congratulated for nothing.
- **A deck of words with no usable sentence** is asserted as its own failure, using the real
  sentence OCR mangled.

## Device checklist for the repo owner

The deck holds 30 cards — 22 words, 7 sentences — of which **6 sentence cards can carry a cloze,
12 blanks in total**. Card 22 cannot: OCR read `XÂM PHẠM` as `XÂM PHAM`.

1. The tab bar reads **書庫 / 已下載 / 練習 / 單字庫** — four tabs.
2. Tap 練習, then Start practice. Five questions, numbered 1/5 through 5/5.
3. **Both answer styles appear** — some questions offer four options, others a text field.
4. The four options are all your own words, and one of them is right.
5. Type an answer with the Vietnamese keyboard. Correct with different capitalisation still
   passes; a wrong tone does not.
6. Answer one wrong on purpose: it names the right word and the round continues — **no repeat
   until correct**, which is stage 4.
7. Finish the round: the summary says either "All correct" or a score, and Done returns to the
   start.
8. **Leave mid-round and come back**: it starts a new round rather than resuming. Nothing is
   recorded in this stage, so there is nothing to resume from.
9. Check the backend afterwards — **no rows were written by playing**.
10. Both phone sizes: a long sentence with a blank wraps rather than truncating, and the four
    option buttons do not overflow.
