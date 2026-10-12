# 14 — Cloze typed

**What to build:** A sentence card that contains one of the reader's own words can now be asked as a cloze: the sentence with that word blanked, its meaning, and a field for the missing word. Which form a card takes is drawn at random from what it supports, so such a card is sometimes a cloze and sometimes a translation; every other card stays a translation.

See the spec's *Question types* and *Judging*, and the two JavaScript traps it names for finding words in a sentence.

**Blocked by:** 12 — A translate session that saves.

**Status:** ready-for-agent

- [ ] A deck word is found in a sentence as a whole word: not inside a longer word (including one with non-ASCII letters), with punctuation and the sentence's ends counting as boundaries
- [ ] Finding is exact about tones — a word differing only by tone is not a match — and tolerant of case and of spacing
- [ ] A cloze is built only from a sentence card, never from a word card or a card with no kind, and a card is never blanked by itself
- [ ] A match that would leave the sentence empty is not used
- [ ] The blank is the matched card with the lowest ladder stage; a tie goes to the earliest in the sentence
- [ ] The prompt is the sentence with the word removed, intact otherwise, plus the sentence's translation
- [ ] The question type is drawn uniformly from what the card supports, with the random source passed in
- [ ] A cloze answer is right when it equals the word as written in the sentence or the matched card's own text; tones are strict, tone placement is folded, and punctuation is not ignored
- [ ] The review is posted as `cloze_typed`
- [ ] Feedback shows the reader's answer and the missing word, and the whole sentence
- [ ] Unit tests cover finding, building, the draw and cloze judging
- [ ] Hand-off: a list for the developer covering a cloze appearing for a sentence that holds a collected word, the blank being the less familiar of two, and a word card never appearing as a cloze
