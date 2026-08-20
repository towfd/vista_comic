Status: draft

# Vocabulary stage 3: a round of cloze you can actually play

Stage 3 of `.scratch/vocabulary-review/prd.md`. Stages 1 and 2 built the deck and somewhere to
repair it. This is the first thing that asks the reader a question.

## Problem Statement

Two stages in, the app collects words and lets them be corrected, and **nothing has ever tested
the reader on one**. The question the whole PRD exists to answer — *will they come back?* — has
had nothing to come back to.

It also cannot be answered by the cheapest thing to build. Matching is the one question type the
architecture deliberately excludes from the ladder: it is a warm-up between the demanding types,
not an assessment. Shipping matching alone would have produced a game whose results mean nothing.

**Cloze is the smallest question type that counts**, and it turned out to be reachable now.

## What the spike changed

Cloze was scheduled behind an LLM breakdown of each sentence into its words. A three-minute spike
against the real deck showed that is not needed, and the reasoning is worth keeping:

**The blank in a cloze is always a word the reader has collected.** Blanking a word they never
chose is not testing them on anything. So the question is not "what are the words in this
sentence" — which for Vietnamese is a genuine NLP problem, since spaces separate *syllables*
rather than words (`đạo luật` is one word, two syllables) — but "which of my cards appear in this
sentence", which is a search against a list already in hand.

The spike, on real cards:

```
SAU KHI THÔNG QUA ĐẠO LUẬT CẤM TRỪNG PHẠT THÂN THÊ VÀO NĂM 2011
                  ↓ deck holds "SAU KHI" and "ĐẠO LUẬT"
SAU KHI THÔNG QUA ____ CẤM TRỪNG PHẠT THÂN THÊ VÀO NĂM 2011
```

It also established two things that shape the rules below:

- **Positions must map back to the original string.** Matching happens on a normalised form with
  whitespace stripped, so a hit at index *i* there is not index *i* in the sentence. Keeping an
  index map means a blank lands correctly even when the source has a double space or a line break
  the OCR carried in — verified against `Sau  khi\nthông qua đạo luật`.
- **The boundary test is what stops `AN` matching inside `THÂN`**, and it works because Vietnamese
  puts spaces between syllables.

## Solution

1. A rule that finds every deck word inside a sentence, as ranges in the original text.
2. Cloze questions built from that: a sentence card with one of its deck words blanked.
3. Two ways to answer: four choices, or typed.
4. A **練習** tab, holding a round of five questions.

No ladder, no three-step day, no scheduling — that is stage 4. This stage exists to make one
round playable and to find out whether it is worth playing.

## User Stories

- As a reader, I open 練習 and answer five questions about words I chose myself.
- As a reader, I see a sentence I collected with one of my own words missing, and pick it out of
  four — all of which are words I have collected, so getting it right means reading all four.
- As a reader who knows a word well, I type it instead of picking it.
- As a reader with too few cards to fill a round, I am told how many more I need rather than
  shown a broken one.

## Implementation Decisions

### Finding deck words in a sentence

A pure function: given a sentence and the deck, return every occurrence of a deck word as a range
in the **original** sentence, with the card it belongs to.

Three rules, all validated by the spike:

1. **Match on the normalised form** (`normalizedKey`), so case, width, double spaces and line
   breaks do not hide a word. This is the same normalisation the deck's identity and 單字庫's
   search already use — there is one definition of "the same text" in this app.
2. **Keep an index map** from the normalised string back to the original, so a match can be
   turned into a range that blanks correctly.
3. **Require a boundary**: the character before and after a hit must not be alphanumeric.

**Rule 3 does not work for Japanese, and that is recorded rather than solved.** Every Japanese
character is alphanumeric, so the test can never pass; without it, a deck word could match inside
a longer one. The library today is Vietnamese, where spaces make the test reliable. When a
non-spaced source language matters, this is where a tokeniser would go — and only then.

### Building a cloze

A card can carry a cloze when it is a **sentence** and at least one deck word occurs in it.

- The blank is one of those deck words. Where several occur, prefer the least familiar — that is
  the one worth testing, and it reuses the familiarity the deck already tracks.
- **A card with no deck word in it produces no cloze**, and the round takes another card rather
  than blanking something arbitrary. Question types follow from what a card can actually support.
  With a small deck this will be common, and it is not an error state.
- A word card produces no cloze in this stage: it has no sentence to blank. Stage 6 generates one.

### Answering

**Four choices**, with distractors drawn from the reader's own other cards. No dictionary and no
generation — and the distractors are themselves revision, since choosing correctly means reading
all four. A deck of fewer than four cards cannot form this question.

**Typed**, judged after the same normalisation, so punctuation and spacing do not matter but
spelling and tones do.

Which one appears is not decided by familiarity yet — there is nothing to decide it with until
the ladder exists. **Stage 3 alternates**, so both interfaces get used and tested; stage 4 makes
it a difficulty ladder.

### The round

Five questions. A round ends when all five are answered.

**Nothing is recorded and nothing is scheduled.** No `card_review` rows, no ladder movement, no
mistakes area. This stage is deliberately a toy: it proves the questions are answerable and worth
answering, and stage 4 is where results start to mean something. Building the recording first
would mean recording results from a round nobody had tried yet.

Wrong answers are shown as wrong and the round continues. The repeat-until-correct rule belongs
with the three-step day, in stage 4.

### The tab

A fourth tab: **書庫 / 已下載 / 練習 / 單字庫**.

Practice is the point of the whole system, where 單字庫 is a workshop the reader should rarely
need. Putting practice behind it would mean walking through the room nobody visits to reach the
thing to do daily. 錯題區 and 單字練習 join this tab later.

## Testing Decisions

The matching rule is where the risk is, and it is a pure function, so it carries most of the
tests. The spike's cases become the suite:

- A deck word is found with the correct range, and blanking that range leaves the rest of the
  sentence untouched.
- Case, double spaces and line breaks do not prevent a match, and the range still maps to the
  original — `Sau  khi\nthông` matches `SAU KHI`.
- `AN` does **not** match inside `THÂN`.
- `THÂN THỂ` does not match `THÂN THÊ` — different tones are different words, exactly as the
  deck's own identity treats them.
- A word occurring twice yields two ranges.
- A sentence with no deck word yields none.

Question building:

- A sentence card with deck words produces a cloze; one without produces none.
- The blank prefers the least familiar of several deck words present.
- A word card produces no cloze.
- Distractors are other cards, never the answer, and never repeated within one question.
- Fewer than four cards means no four-choice question.

Typed answers: correct ignoring punctuation and spacing; wrong on a changed tone; wrong on a
missing word.

**No XCUITest is written, built, or run.** UI verification is handed over as a checklist: the
round on both phone sizes, a deck too small to form a round, a wrong answer, a typed answer with
the Vietnamese keyboard, and the tab bar with four tabs.

## Out of Scope

- The ladder, the three-step day, `card_review`, and any scheduling (stage 4).
- Sentence translation and word rearrangement (stage 5).
- Practice-sentence generation, and therefore cloze on word cards (stage 6).
- 錯題區 and 單字練習 (stage 7).
- Streaks, XP, and anything that persists between rounds (stage 8).
- Choosing the answer mode by familiarity — nothing yet knows how familiar a card is.
- A tokeniser for non-spaced languages.

## Further Notes

This is the stage that finally tests the PRD's premise, and it is worth being honest about how
small the evidence will be. The deck is a handful of cards, several of them the same Vietnamese
sentence with different OCR readings, so the first rounds will be repetitive. What can be learned
is whether answering is pleasant and whether the reader opens the tab again — not whether the
system teaches anything, which needs far more cards and far more time.
