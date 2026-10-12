# 14 — Cloze typed

**What to build:** A sentence card that contains one of the reader's own words can now be asked as a cloze: the sentence with that word blanked, its meaning, and a field for the missing word. Which form a card takes is drawn at random from what it supports, so such a card is sometimes a cloze and sometimes a translation; every other card stays a translation.

See the spec's *Question types* and *Judging*, and the two JavaScript traps it names for finding words in a sentence.

**Blocked by:** 12 — A translate session that saves.

**Status:** done (2026-10-12) — merged; the browser checklist below is still the developer's to run

- [x] A deck word is found in a sentence as a whole word: not inside a longer word (including one with non-ASCII letters), with punctuation and the sentence's ends counting as boundaries
- [x] Finding is exact about tones — a word differing only by tone is not a match — and tolerant of case and of spacing
- [x] A cloze is built only from a sentence card, never from a word card or a card with no kind, and a card is never blanked by itself
- [x] A match that would leave the sentence empty is not used
- [x] The blank is the matched card with the lowest ladder stage; a tie goes to the earliest in the sentence
- [x] The prompt is the sentence with the word removed, intact otherwise, plus the sentence's translation
- [x] The question type is drawn uniformly from what the card supports, with the random source passed in
- [x] A cloze answer is right when it equals the word as written in the sentence or the matched card's own text; tones are strict, tone placement is folded, and punctuation is not ignored
- [x] The review is posted as `cloze_typed`
- [x] Feedback shows the reader's answer and the missing word, and the whole sentence
- [x] Unit tests cover finding, building, the draw and cloze judging
- [x] Hand-off: a list for the developer covering a cloze appearing for a sentence that holds a collected word, the blank being the less familiar of two, and a word card never appearing as a cloze

## Comments

Implemented 2026-10-12. 218 unit tests pass; the type check and production build are clean. The page was not opened in a browser.

**Run once against the real deck**, read-only, with a throwaway test that was then deleted: of 249 cards, 105 are sentences and **98 of them yield a cloze**. The word removed ranges from 3 to 38 characters — the long ones are where one collected line sits whole inside a longer one, which the phone does too. No sentence holds more than three deck words. 219 cards are entirely upper case, so ignoring case is doing real work; 8 hold a syllable whose tone placement varies by convention; none is stored in a decomposed form.

The draw is even: a card that supports both is a cloze half the time. Feedback for a cloze shows the reader's answer, the missing word as the sentence wrote it, and the whole sentence.

**For the developer to check in the browser:**

- Over a session, sentence cards appear sometimes as 填入空格裡的字 — the sentence with a gap and its meaning underneath — and sometimes as a translation. A word card is always a translation.
- The gap replaces one of your own collected words, and the rest of the sentence reads exactly as on the phone, line breaks included.
- For a sentence holding two of your words, the gap is the one you know less well (compare their stages on the phone).
- Type the missing word in lower case when the card is in capitals: 正確.
- Type it without its tone: 不對. Type it with a full stop after it: 不對.
- After the verdict the feedback shows the missing word and the whole sentence.
- In the network panel a cloze answer's `POST` body has `"questionType":"cloze_typed"`; a translation's has `"sentence_typed"`.
- A long gap — a whole phrase — still fits a narrow window without the page scrolling sideways.
