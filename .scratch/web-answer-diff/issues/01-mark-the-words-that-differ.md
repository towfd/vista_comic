# 01 — Mark the words that differ

**What to build:** On the web practice feedback screen, a wrong answer marks in red the words of 你的答案 that are not in the card, and the words of the card that the answer missed or got wrong. See [the spec](../spec.md).

**Blocked by:** None — can start immediately.

**Status:** done (2026-11-24) — on `feature/web-answer-diff`; checked in the browser with a stubbed API, device checks pending

**Notes from implementation**

- The judge's per-syllable fold is now `syllableKey` in `text.ts`, shared by the judge and the marking, so the two cannot drift apart.
- The marking lives in `practice/answerDiff.ts`; the screen only renders its pieces.
- Checked in Chromium at 390 and 1024 wide, light and dark, with every backend request answered in the browser (nothing reached the real deck): a wrong sentence marks the wrong and missed words on both lines; 算我對 removes the marks.

**Acceptance criteria**

- [x] A wrong sentence answer marks its differing words in 你的答案, and the missed or wrong words in the card line
- [x] A wrong cloze answer marks against 空格裡的字
- [x] Case, punctuation (in a sentence) and tone placement never cause a mark
- [x] Spacing and punctuation between words are shown as typed and never marked
- [x] Marks are red and underlined; none on a correct or overridden answer
- [x] Vitest covers the marking; the web suite, `vue-tsc` and the build pass

**Developer device checklist**

- A wrong sentence with one wrong tone: only that word is red in 你的答案, and the right word is red in 卡片
- A sentence with a word left out: nothing extra is red in 你的答案; the missing word is red in 卡片
- A wrong cloze: the typed word and 空格裡的字 are red
- 算我對 on a wrong answer: the red goes away
- Dark mode: the red is readable on both lines
