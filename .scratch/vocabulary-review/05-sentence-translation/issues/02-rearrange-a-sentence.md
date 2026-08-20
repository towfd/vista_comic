# 02 — Rearrange a sentence

**What to build:** The scrambled-pieces question: the answer's own words, shuffled, to be put back in order.

No distractors. The question is whether the reader knows how the sentence goes, and ordering is where Vietnamese grammar lives.

**Split on spaces**, which for Vietnamese means splitting on *syllables* — `ĐẠO LUẬT` becomes two pieces even though it was collected as one word. Keeping deck words whole is the alternative and needs the deck as a word list; splitting has no dependency and one rule. **The deck's sentences are long, so expect twelve to fifteen pieces** — if that proves miserable on a device, keeping deck words whole is a change to one function rather than to the design.

**Only sentence cards.** Six word cards in the deck are a single syllable, so there would be one piece and nothing to arrange; most of the rest are two, where guessing is right half the time.

**Judge the assembled string, never the arrangement.** Two sentences in the deck repeat a word — `CÒN` and `MÌNH` in one, `LỢI` in another — so the screen shows identical pieces the reader cannot tell apart, and **both placements are correct**. Checking which tile went where would mark a right answer wrong.

**Blocked by:** 01.

**Status:** not started.

- [ ] The pieces are exactly the answer's words, split on whitespace, and every one is offered
- [ ] The shuffle never presents them already in order
- [ ] Assembling them correctly is correct, judged through ticket 01's function
- [ ] A sentence repeating a word offers two identical pieces, and **either placement is accepted** — asserted against the two real sentences that do this
- [ ] A word card never produces a rearrangement
- [ ] A sentence of one word produces none either
- [ ] Pieces can be placed and taken back before answering
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
