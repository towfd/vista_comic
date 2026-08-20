# 02 — Build a cloze question from a card

**What to build:** The rule that turns a card into a question, or decides it cannot.

A card carries a cloze when it is a **sentence** and at least one deck word occurs in it. The blank is one of those words; four choices come from the reader's other cards.

**Which word gets blanked: the least familiar one present.** That is the one worth testing, and it reuses familiarity the deck already tracks rather than inventing a second idea of what needs practice.

**A card that cannot carry a cloze produces nothing, and the round moves on.** Question types follow from what a card actually supports — never from blanking something arbitrary to fill a slot. With a small deck this will be common and it is not an error state. A **word** card produces no cloze at all in this stage: it has no sentence to blank, and generating one is stage 6.

**Distractors are the reader's own cards**, so no dictionary and no generation is involved — and they are revision in their own right, since choosing correctly means reading all four. Fewer than four cards means no four-choice question can be built.

**Blocked by:** 01.

**Status:** not started.

- [ ] A sentence card containing a deck word produces a cloze whose blank is that word
- [ ] Where several deck words occur, the least familiar is blanked
- [ ] A sentence card containing no deck word produces no question
- [ ] A word card produces no question
- [ ] Distractors are other cards, never the answer, and never repeated inside one question
- [ ] Fewer than four cards produces no four-choice question
- [ ] A typed answer is judged after the same normalisation: punctuation and spacing are ignored, spelling and tones are not
- [ ] A typed answer with a changed tone is wrong
- [ ] Question building is pure — cards in, questions out, no repository
