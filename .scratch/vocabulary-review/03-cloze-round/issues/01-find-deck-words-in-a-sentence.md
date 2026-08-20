# 01 — Find the deck's words inside a sentence

**What to build:** A pure function. Given a sentence and the reader's cards, return every place a deck word occurs, as a range in the **original** sentence, with the card it belongs to.

Nothing is visible when this lands. It goes first because it is where the risk is, it needs no device to verify, and every question type after it depends on being able to point at a word inside a sentence.

**This replaces a whole stage of LLM work, and the reasoning matters more than the code.** Cloze was scheduled behind a model breaking each sentence into words. It does not need one, because **the blank in a cloze is always a word the reader collected** — blanking something they never chose is not testing them. So the question is not "what words is this sentence made of", which for Vietnamese is a real problem (spaces separate *syllables*: `đạo luật` is one word in two pieces), but "which of my cards are in here" — a search against a list already in hand.

Three rules, each established by running them on the real deck:

1. **Match on the normalised form** (`normalizedKey`), so case, width, doubled spaces and OCR line breaks cannot hide a word. Same normalisation the deck's identity and 單字庫's search already use — there is one definition of "the same text" in this app and it stays that way.
2. **Keep an index map back to the original.** Matching happens on a string with whitespace stripped, so a hit at index *i* there is not index *i* in the sentence. Without the map, a blank lands in the wrong place the moment the source has a double space — which the reader's own cards already do.
3. **Require a boundary**: the characters either side of a hit must not be alphanumeric.

**Rule 3 cannot work for Japanese, and this ticket does not try.** Every Japanese character is alphanumeric, so the test can never pass; dropping it would let a deck word match inside a longer one. The library is Vietnamese, where spaces make it reliable. A tokeniser belongs here and only when a non-spaced source language actually matters.

**Blocked by:** nothing.

**Status:** implemented on branch `feat/cloze-round`, 2026-08-20 — `exit 0`, 393 passed, zero failures. Backend untouched; nothing user-visible.

- [x] A deck word in a sentence is returned with a range that blanks it exactly, leaving the rest of the sentence byte-for-byte intact
- [x] Case differences do not prevent a match
- [x] Doubled spaces and line breaks inside the sentence do not prevent a match, and the range still maps to the original — `Sau  khi\nthông` matches a card holding `SAU KHI`
- [x] Full-width and half-width forms match, following `normalizedKey`
- [x] `AN` does **not** match inside `THÂN`
- [x] A card holding `THÂN THỂ` does not match `THÂN THÊ` — different tones are different words, exactly as the deck's identity already treats them
- [x] A word occurring twice returns two ranges
- [x] A sentence containing no deck word returns nothing, and that is not an error
- [x] A card whose text normalises to empty matches nothing
- [x] The function takes cards and a sentence and touches no repository, so it is testable with literals

## What was built

`Features/Study/DeckWordMatching.swift` — `deckWords(in:from:)` returning matches as ranges in the
original sentence, plus `String.blanking(_:)`.

The index map is the load-bearing part. Comparison happens on a whitespace-stripped form, so a hit
at offset *i* there is not offset *i* in the sentence; without the map a blank lands in the wrong
place the moment the source has a doubled space — which the reader's own cards already do.

## Verification

14 tests, and **the cases are not invented**. They came from running the rule against the real
30-card deck before the Swift existed, so a regression shows up as something that stopped working
on real data:

- `AN` does not match inside `THÂN` — the specific failure the boundary test exists for.
- `THÂN THỂ` does not match `THÂN THÊ`, and a suite of sentences taken verbatim from the deck
  yields exactly the blanks the spike found.
- One real sentence yields nothing, because OCR read `XÂM PHẠM` as `XÂM PHAM`. **The test asserts
  the refusal**, with a comment saying the fix is correcting the card in 單字庫 — not loosening
  the rule until wrong words match. Tones are part of a Vietnamese word: `cấm` (forbid) is not
  `câm` (mute).
- Punctuation counts as a boundary, since real sentences end in full stops.
