Status: ready-for-agent

# Web practice: mark the words that differ

## Problem Statement

When a typed answer is judged 不對, the feedback screen shows 你的答案 and the card's text one above the other, and the reader has to compare them a word at a time to find what was wrong. A sentence of ten syllables with one wrong tone is a slow hunt.

## Solution

On a wrong answer, the words that differ are marked in red: in 你的答案, the words that are not in the card; in the card's line, the words the answer is missing or got wrong. Everything that matches stays as it is.

## User Stories

1. As a reader, when my answer is wrong, I want the wrong words in my answer shown in red, so I see the mistake at a glance.
2. As a reader, when I left a word out, I want that word marked in the card's line, so a missing word is as visible as a wrong one.
3. As a reader, I want a word that differs only in a way the judge ignores (case, punctuation in a sentence, where the tone mark sits) never marked, so red always means something the judge counted.
4. As a reader, once I press 算我對, I want the marks gone, since the answer now counts as right.

## Implementation Decisions

- Web only; no backend or iOS change.
- Words are compared with the judge's own per-syllable key: compatibility-composed, lower-cased, with the tone marks lifted off the vowel. A sentence ignores punctuation and symbols, as its judge does; a cloze does not.
- The two texts are aligned by longest common subsequence of those keys. A word of the answer outside it is marked; a word of the expected text outside it is marked.
- Spaces and punctuation between words are kept exactly as written and never marked.
- Marked words are red **and underlined**, so the mark does not rest on colour alone (DESIGN.md: 顏色只是輔助).
- Marks appear only while the verdict is wrong; an overridden or correct answer shows plain text.
- A cloze compares against the word that was blanked, which is what the screen shows as 空格裡的字.
- Accepted: an answer wrong in two ways at once — spacing and a letter — can mark a run-together word whole, since the judge too counts such an answer wrong.

## Testing Decisions

- The marking is a pure function in `web/src/practice/`, covered by vitest.
- No component tests; the developer checks the screen (device checklist on the ticket).

## Out of Scope

- iOS.
- Marking at the level of a letter within a word.
- Changing how answers are judged.
