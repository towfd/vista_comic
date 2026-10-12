Type: research
Status: resolved

# What the engine must reproduce

## Question

What, exactly, does a TypeScript port of the phone's practice logic have to reproduce, and where can it silently disagree with the original?

An inventory of `ClozeQuestion.swift`, `DeckWordMatching.swift`, `SentenceAnswer.swift`, `PracticeQueue.swift` and `PracticeRound.swift`, together with their tests: each rule, what it reads off a card and off the settings, which `GET /cards` fields it depends on, and where randomness and the clock enter. Per question type, what it costs to port on its own — so [the thin slice](02-the-thin-slice.md) can be cut knowing the price of each piece.

Particular attention to text normalisation: the tone-insensitive, punctuation-insensitive and identity keys, how the backend's `normalization.py` relates to them, and whether JavaScript's `String.prototype.normalize` and casing produce the same keys for Vietnamese (`đ`, precomposed against combining forms, what an input method on macOS actually emits).

## Answer

The full inventory is [`assets/engine-inventory.md`](../assets/engine-inventory.md) (353 lines, written 2026-10-12 by a read-only research subagent; it marks what was run against what was only read). What later tickets need from it:

**Normalisation ports exactly for Vietnamese.** 44 inputs were run through the real Swift functions, the real `normalization.py` and Node; every Vietnamese input — precomposed, combining, `đ`/`Đ`, mixed case — produced the same three keys in all of them, given these JavaScript forms:

- identity key: `normalize('NFKC')`, strip `\p{White_Space}`, `toLowerCase()`
- tone key: `đ`→`d`, then NFD, then strip the fixed range U+0300–U+036F
- punctuation key: strip `[\p{P}\p{S}]`

The obvious spellings are the wrong ones: `\s` disagrees with Swift on U+0085 and U+FEFF, and `\p{M}` in place of the fixed range changes keys outside Vietnamese. Only the identity key exists in Python; the tone and punctuation keys are Swift-only, and the shared vector table holds no Vietnamese vector.

**What each piece costs**, in lines of code excluding comments:

| Piece | Lines | Cards it can ask |
|---|---|---|
| Translate | ~13 | every card |
| Rearrange | ~65 | sentence cards with more than one piece |
| Cloze, typed | ~90 | sentence cards containing a deck word |
| Cloze, four choices | ~100 | the same, with at least three distractors available |
| The queue | ~55 | — needed whatever the modes |

The second cloze mode costs ~12–25 lines after the first, since both need all of `DeckWordMatching`. Translate is the only mode that can ask every card, word cards included. 99 tests pin the five files.

**Where a port can silently disagree**, in the order the inventory ranks them:

1. The phone moves a card with its own scheduler before the response arrives and does not wait for it. A web queue rebuilt before the response lands offers the same card again — and the server's guard against an early answer covers review cards only, not learning steps.
2. `today` must be the reader's local day; `toISOString()` gives the UTC one.
3. `\b` is ASCII-only in JavaScript, so `ÀO` matches inside `CHÀO`.
4. Swift matches per grapheme and compares by canonical equivalence; JavaScript works in code units.
5. Tie-breaks depend on the order `GET /cards` returns.

No randomness is injectable in the Swift code, and `docs/api-contract.md` does not cover the card routes.

## Comments

Hazard 1 bears directly on [An answer that cannot be posted](07-an-answer-that-cannot-be-posted.md) and [The queue under two clients](03-the-queue-under-two-clients.md); the missing Vietnamese vector on [Keeping two engines in step](05-keeping-two-engines-in-step.md). The findings are the subagent's and have not been re-verified line by line in the main session.
