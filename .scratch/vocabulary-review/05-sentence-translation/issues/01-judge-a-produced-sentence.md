# 01 — Judge a produced sentence

**What to build:** The rule that says whether what the reader produced is the answer — used by both typing and rearranging.

It is the same normalisation the deck already agrees on: punctuation and spacing never matter, spelling and **word order** do. A missing tone counts and is named, exactly as stage 3 settled for cloze, because typing tones on a phone is laborious and rejecting an otherwise perfect answer over one charges the reader for typing rather than testing recall.

**The leniency stays in judging.** Card identity and finding deck words inside a sentence remain strict — `leniencyReachesTypingOnly` already asserts both boundaries, and this ticket must not weaken it.

**A wrong answer shows the correct sentence beside what was typed, and no more.** Marking up the differences is a whole algorithm — including deciding whether a tone slip counts as "different" — for a screen the reader glances at. Duolingo shows the sentence and lets them compare; so does this.

**Blocked by:** nothing.

**Status:** not started.

- [ ] The exact sentence is correct
- [ ] Case, spacing and punctuation differences are still correct
- [ ] A missing or wrong tone is correct-and-named, matching cloze's existing verdict type
- [ ] The right words in the wrong order are **wrong** — this is the point of the question type
- [ ] A different word is wrong
- [ ] An empty answer is wrong rather than vacuously right
- [ ] A word card's single word is judged by the same function, with no special case
- [ ] Nothing here changes `normalizedKey` or what `deckWords` matches
