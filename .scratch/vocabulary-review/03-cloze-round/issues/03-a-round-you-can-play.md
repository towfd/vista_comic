# 03 — A round you can play

**What to build:** A **練習** tab holding a round of five cloze questions, answerable by choosing or by typing.

This is the first time the app asks the reader anything, and the first evidence about the question the whole PRD exists to answer: *will they come back?*

**Nothing is recorded.** No `card_review` rows, no ladder movement, no mistakes area. This round is deliberately a toy — it proves the questions are answerable and worth answering, and stage 4 is where results start to mean something. Building the recording first would mean recording results from a round nobody had tried.

For the same reason a wrong answer is simply shown as wrong and the round continues; the repeat-until-correct rule belongs with the three-step day in stage 4.

**Answer modes alternate.** Nothing yet knows how familiar a card is, so nothing can choose between four-choice and typed — alternating gets both interfaces exercised, and stage 4 replaces the alternation with the real difficulty ladder.

**A fourth tab: 書庫 / 已下載 / 練習 / 單字庫.** Practice is the point of the whole system, where 單字庫 is a workshop the reader should rarely need. Putting practice behind it would mean walking through the room nobody visits to reach the thing to do daily.

**Blocked by:** 02.

**Status:** not started.

- [ ] A 練習 tab exists; the tab bar has four tabs
- [ ] A round presents five questions and ends when all five are answered
- [ ] Both answer modes appear across a round
- [ ] A correct answer is confirmed; a wrong one shows what the answer was and the round continues
- [ ] A deck too small to build a round says how many more words are needed, rather than showing a broken round
- [ ] A deck with no sentence cards says so distinctly — nothing is wrong, there is simply nothing to blank yet
- [ ] Leaving mid-round and returning does not resume a half-finished round; it starts a new one, since nothing is being recorded
- [ ] Nothing is written to the backend by playing
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
