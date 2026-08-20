# 01 — Judge a produced sentence

**What to build:** The rule that says whether what the reader produced is the answer — used by both typing and rearranging.

It is the same normalisation the deck already agrees on: punctuation and spacing never matter, spelling and **word order** do. A missing tone counts and is named, exactly as stage 3 settled for cloze, because typing tones on a phone is laborious and rejecting an otherwise perfect answer over one charges the reader for typing rather than testing recall.

**The leniency stays in judging.** Card identity and finding deck words inside a sentence remain strict — `leniencyReachesTypingOnly` already asserts both boundaries, and this ticket must not weaken it.

**A wrong answer shows the correct sentence beside what was typed, and no more.** Marking up the differences is a whole algorithm — including deciding whether a tone slip counts as "different" — for a screen the reader glances at. Duolingo shows the sentence and lets them compare; so does this.

**Blocked by:** nothing.

**Status:** implemented on branch `feat/sentence-translation`, 2026-08-20 — backend `282 passed`; iOS covered by `SentenceAnswerTests`.

- [x] The exact sentence is correct
- [x] Case, spacing and punctuation differences are still correct
- [x] A missing or wrong tone is correct-and-named, matching cloze's existing verdict type
- [x] The right words in the wrong order are **wrong** — this is the point of the question type
- [x] A different word is wrong
- [x] An empty answer is wrong rather than vacuously right
- [x] A word card's single word is judged by the same function, with no special case
- [x] Nothing here changes `normalizedKey` or what `deckWords` matches

## What was built

`Features/Study/SentenceAnswer.swift` — `judgeSentenceAnswer`, and
`punctuationInsensitiveKey` in `TextNormalization.swift`.

**A test written from the spec found the spec wrong.** It had claimed since stage 3 that
"punctuation and spacing" were both ignored — and only spacing ever was. `normalizedKey` keeps
punctuation on purpose, because it backs card identity and two lines differing by a full stop are
two things the reader framed differently.

Judging wants the opposite: the deck's sentences end in `.` and `,` (`CHO BẢN THÂN.`,
`MÌNH NỮA,`), so marking a perfect answer wrong over a missing full stop would charge for
punctuation rather than test recall. So punctuation is stripped **in judging only**, layered on
top of `normalizedKey` exactly as tone-forgiveness already is — and the spec is corrected rather
than the claim quietly left standing.
