Status: ready-for-agent

# Vocabulary stage 5: producing the language, and a difficulty that means something

Stage 5 of `.scratch/vocabulary-review/prd.md`. Stage 4 made answers count. This adds the
question type that asks the reader to produce Vietnamese rather than recognise it, and turns the
question types into an actual difficulty ladder.

## Problem Statement

Two problems, and the second was found by looking at the real deck rather than by planning.

**Everything so far is recognition.** Cloze offers four words to choose between, or asks for one
word inside a sentence the reader can already see. Nothing has ever asked them to produce a
sentence, which is the thing they say they want — reading these comics in the original — and the
thing recognition does not get you to.

**Half the deck is never asked about.** Of twenty-two word cards, **eleven appear in no sentence
card**, so no cloze can be built from them:

```
BÓNG DÁNG   NGUYÊN TẮC   ÁP DỤNG    XÂM PHẠM    THẨM QUYỀN   Kiềm CHẾ
BẤT CẬP     PHÁ HUỶ      BỊ LÔI RA  QUỐC HỘI    NGUY
```

They are collected, listed, and counted on the practice card — and never practised. Generation
would have solved it, and generation is parked. **A word card asked to be translated needs
nothing generated**, so this stage closes the gap as a side effect of the question type it was
already going to build.

## Solution

1. **句子翻譯**: Chinese shown, Vietnamese produced — by typing, or by ordering scrambled pieces.
2. The same question applied to **word cards**, which is how the eleven orphans get practised.
3. Question type chosen by familiarity, so the round has a difficulty curve.

## User Stories

- As a reader, I am shown the meaning and asked to produce the Vietnamese, which is what reading
  the comic actually asks of me.
- As a reader meeting a card I barely know, I get pieces to arrange rather than a blank box.
- As a reader who knows a card well, I type it out.
- As a reader, the words I collected on their own get practised too, instead of sitting in the
  deck being counted.

## Implementation Decisions

### Chinese → Vietnamese, and the direction is the point

The prompt is the card's translation; the answer is its source text. Producing the target
language is the harder and more valuable direction, and the developer types Vietnamese
comfortably — a constraint that was checked before choosing it, because the reverse direction
would have been much easier to build and worth much less.

### Judged by the deck's own normalisation, tones forgiven and named

Punctuation and spacing never matter; spelling and word order do.

**Spacing is `normalizedKey`, which the deck's identity, 單字庫's search and cloze's typed answers
already use. Punctuation is stripped separately, on top of it.** That distinction was found by a
test written from this spec: the spec had been claiming since stage 3 that "punctuation and
spacing" were both ignored, and only spacing ever was. `normalizedKey` keeps punctuation on
purpose — it backs card identity, and two lines differing by a full stop are two things the reader
framed differently. Judging wants the opposite, and the deck's sentences end in `.` and `,`, so
marking a perfect answer wrong over a missing full stop would charge for punctuation rather than
test recall.

**A missing tone counts and is called out**, exactly as stage 3 settled for cloze: typing tones
on a phone is laborious, and rejecting an otherwise perfect answer over one charges the reader
for typing rather than testing recall — while silently accepting it would teach that Vietnamese
tones are decoration.

The leniency stays in judging. Card identity and finding deck words inside a sentence remain
strict, and `leniencyReachesTypingOnly` already asserts both boundaries.

### Rearranging: split on spaces, every piece from the sentence itself

The pieces are the answer's own words, shuffled. No distractors: the question is whether the
reader knows how the sentence goes, and ordering is where Vietnamese grammar lives.

**Split on spaces**, which for Vietnamese means splitting on *syllables* — `ĐẠO LUẬT` becomes two
pieces even though the reader collected it as one word. The alternative, keeping deck words
whole, needs the deck as a word list and is a real option; splitting was chosen for having no
dependency and one rule.

**Only sentence cards are rearranged.** Six of the deck's word cards are a single syllable, so
there would be one piece and nothing to arrange; most of the rest are two, where guessing is right
half the time. A word card in that difficulty band is typed instead — question types follow from
what a card can support, which is the rule since stage 3.

**Judging compares the assembled string, not the arrangement.** Two sentences in the deck repeat a
word (`CÒN` and `MÌNH` in one, `LỢI` in another), so the screen will show identical pieces that the
reader cannot tell apart — and both placements are correct. Checking which tile went where would
mark a right answer wrong.

The consequence is real and should be watched during the device pass: the deck's sentences are
long, so a rearrangement will offer **twelve to fifteen pieces**. If that turns out to be
miserable, keeping deck words whole is a change to one function rather than to the design.

### Difficulty follows the **ladder rung**, not the day

Stage 3 alternated answer modes because nothing knew how familiar a card was. Stage 4 built two
things that do, and the first draft of this spec quietly used both — the table read 不熟/熟悉
for its first two rows and "higher rungs" for the third, mixing the two clocks in the one document
that insists on keeping them apart.

**The rung, not the day.** A card's difficulty should reflect how well the reader knows it over
weeks, which is what the rung measures. Using the day would mean every card starts each morning
at four-choice, including words learned months ago — and would make a card's two appearances in
one round differ in difficulty, so the second is harder purely because the first went well.

| Ladder rung | What is asked |
|---|---|
| 0–1 | Cloze, four choices — recognition |
| 2–3 | Cloze typed, or a rearrangement — production with support |
| 4 | Sentence translation, typed — production from nothing |

The whole deck sits on rung 0 today, so **every question will be four-choice until cards start
climbing** — which is correct rather than a defect, and worth expecting during the device pass.

**A card that cannot carry the type its familiarity calls for falls back to one it can.** A word
card has no cloze; a sentence with no deck word in it has none either. Question types follow from
what a card supports, as they have since stage 3.

## Testing Decisions

Judging:

- Correct ignoring punctuation, spacing and case.
- A wrong answer shows the full correct sentence beside what was typed, and no more. Following
  Duolingo: comparing them is the reader's job and marking up the differences is a whole
  algorithm — including deciding whether a tone slip counts as "different" — for a screen they
  glance at.
- A missing tone is correct-with-a-note; a different word is wrong.
- Word order matters: the right words in the wrong order is wrong.
- An empty answer is wrong rather than vacuously right.

Rearranging:

- The pieces are exactly the answer's words, and every one is used.
- The shuffle never presents them already in order.
- A word card never produces a rearrangement, at any rung.
- A sentence repeating a word yields two identical pieces, and **either placement is accepted** —
  asserted against the two real sentences that do this.
- Assembling them in the right order is correct; any other order is not.

Selection:

- Each **rung** asks what the table says, and the day's step changes nothing about which type
  appears.
- A card's two appearances in one round are the same difficulty.
- A word card never gets a cloze, whatever its familiarity.
- A sentence with no deck word never gets a cloze.
- **The eleven orphaned word cards are askable**, asserted against the real deck's shape.

**No XCUITest is written, built, or run.**

## Out of Scope

- 錯題區 and 單字練習 (stage 6).
- Streaks, XP, days in a row (stage 7).
- Practice-sentence generation, still parked.
- Distractor pieces in a rearrangement.
- Keeping deck words whole when splitting — recorded above as the fallback if fifteen pieces
  proves unusable.
- Any judging cleverer than normalisation: no synonyms, no near-misses, no AI. The card holds one
  translation and that is what is being asked for.

## Further Notes

After this, every card in the deck can be asked about and every question type moves the ladder.
That is the whole loop the PRD describes, minus the parts deliberately left out — which makes
this the point where using it for a few weeks starts to answer the question the PRD exists for.
