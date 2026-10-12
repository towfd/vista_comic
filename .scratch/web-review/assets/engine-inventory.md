# Engine inventory — what a TypeScript port of the practice logic must reproduce

Research asset for [issue 01](../issues/01-what-the-engine-must-reproduce.md). Read-only survey of the tree at `bf8e925` (2026-10-12). No recommendations about the first slice are made here.

Path shorthand: `Study/` = `vista_comic/vista_comic/Features/Study/`, `Net/` = `vista_comic/vista_comic/Networking/`, `Tests/` = `vista_comic/vista_comicTests/`.

**Evidence labels.** `[ran]` = observed by executing code on this machine (Node 26.7.0 / Unicode 17.0 / ICU 78.3; Python 3.10.2 / Unicode 13.0 importing the real `backend/app/normalization.py`; the Swift functions copied verbatim into a script run with the macOS `swift` 6.0.2 interpreter, macOS 15 Foundation). `[read]` = inferred from reading source. Nothing was run on iOS, in a browser, or against the real database.

---

## 1. Rule inventory

Columns: **card** = `LearningCard` fields read; **set** = `StudySettings`; **clock**; **rand** = random source.

### `Net/TextNormalization.swift` (101 lines, 21 of code) — not in the ticket's list of five, but every judging and matching rule calls it

| Rule | Lines | What it does |
|---|---|---|
| `normalizedKey(_:)` | 41–50 | NFKC → drop every `Character` whose `isWhitespace` is true → `lowercased()`. Card identity key; punctuation kept. |
| `toneInsensitiveKey(_:)` | 74–81 | `normalizedKey` → replace `đ` (U+0111) with `d` → NFD → drop scalars U+0300…U+036F. Result stays decomposed. |
| `punctuationInsensitiveKey(_:)` | 96–101 | `normalizedKey` → drop scalars in `CharacterSet.punctuationCharacters` or `CharacterSet.symbols`. |

Pure string functions: no card, settings, clock or randomness.

### `Study/DeckWordMatching.swift` (111 lines, 53 of code)

| Rule | Lines | card | Notes |
|---|---|---|---|
| `normalizedWithOrigins(_:)` (private) | 38–51 | — | Walks the sentence one **grapheme** at a time; NFKCs that grapheme; for each resulting `Character` (the loop variable is named `scalar` but iterates `Character`s) skips whitespace, appends its lowercase, and records the original grapheme's index. Produces the haystack plus a key-position → source-index map. |
| `deckWords(in:from:)` | 71–94 | `sourceText` of every deck card | For each card, in deck order: needle = `normalizedKey(card.sourceText)`; empty needle skipped (77–78). Finds **every** occurrence, overlapping ones included (`searchStart` advances one character, line 90). Maps the hit back to a range in the original sentence (82–85). Keeps it only if `isOnABoundary`. Result sorted by `range.lowerBound` (93). |
| `isOnABoundary(_:in:)` (private) | 97–104 | — | The grapheme immediately before and after the range, in the **original** sentence, must not be `isLetter` or `isNumber`; start/end of string count as boundaries. |
| `String.blanking(_:with:)` | 106–110 | — | Replaces the range with `"____"` (four underscores); everything else byte-for-byte intact. |

No settings, clock, or randomness. The deck passed in is the caller's choice (`makeCloze` passes the deck minus the sentence card).

### `Study/ClozeQuestion.swift` (185 lines, 81 of code)

| Rule | Lines | card | rand | Notes |
|---|---|---|---|---|
| `ClozeQuestion` | 16–39 | — | **yes** | Fields `card`, `answer`, `prompt`, `removed`, `distractors`. `choices` (36–38) is a **computed property** returning `([answer] + distractors).shuffled()`, or `[]` when there are no distractors. It reshuffles on every access. `id` (32) uses `prompt.hashValue` (per-process seed; not portable, not needed). |
| `clozeChoiceCount` | 42 | — | — | `4`. |
| `makeCloze(from:deck:choiceCount:)` | 54–83 | `kind`, `id`, `sourceText`, `ladderStage` | via `distractors` | `nil` unless `card.kind == .sentence` (59). `others` = deck without this card's `id` (66). Matches = `deckWords(in: card.sourceText, from: others)` minus any match that `coversEverything` (67–68). Chosen match = lowest `ladderStage` of the matched card, tie → earliest `range.lowerBound` (69–72); `min(by:)` returns the first of equal elements `[ran]`. `removed` = the original substring, original casing (78). Distractors requested: `choiceCount - 1`. |
| `coversEverything(_:of:)` (private) | 89–94 | — | — | Sentence with the range deleted, then `.trimmingCharacters(in: .whitespacesAndNewlines)`, is empty. |
| `distractors(for:from:count:)` | 104–119 | `id`, `sourceText` | **yes** | Pool = whole deck (the sentence card itself is **not** excluded here) where `id != answer.id`, `normalizedKey` differs from the answer's, and `isPlausibleOption`. Fewer than `count` → `[]`. Else `pool.shuffled().prefix(count)`. No filter on `kind` or `targetLanguage`. |
| `pieceCount(_:)` | 126–128 | — | — | `split(whereSeparator: \.isWhitespace).count` (empty pieces omitted). |
| `isPlausibleOption(_:beside:)` | 140–142 | `sourceText` | — | `pieceCount(candidate) <= max(pieceCount(answer) + 1, 3)`. |
| `TypedVerdict` | 145–155 | — | — | `.correct`, `.correctApartFromTones`, `.wrong`; `isCorrect = self != .wrong`. |
| `judgeClozeAnswer(_:for:)` | 168–180 | `answer.sourceText` | — | `normalizedKey(typed)` empty → `.wrong`. Equal to `normalizedKey(removed)` or `normalizedKey(answer.sourceText)` → `.correct`. Else `toneInsensitiveKey(typed)` equal to either tone key → `.correctApartFromTones`. **Punctuation is not stripped here.** |
| `isCorrectClozeAnswer` | 183–185 | — | — | `judgeClozeAnswer(...).isCorrect`. |

No settings and no clock. Four-choice answers are judged in the view by **id**, not text: `choice.id == item.question?.answer.id` (`Study/PracticeView.swift:382`).

### `Study/SentenceAnswer.swift` (186 lines, 65 of code)

| Rule | Lines | card | rand | Notes |
|---|---|---|---|---|
| `judgeSentenceAnswer(_:for:)` | 34–43 | `sourceText` | — | `punctuationInsensitiveKey(produced)` empty → `.wrong`. Equal to the card's → `.correct`. Else compare `punctuationInsensitiveKey(toneInsensitiveKey(x))` on both sides → `.correctApartFromTones` or `.wrong`. Word order matters (plain string equality after whitespace removal). Works for any card kind. |
| `sentencePieces(of:)` | 53–55 | `sourceText` | — | Split on `Character.isWhitespace`, empties omitted. Punctuation stays attached to its piece (`NỮA,`). |
| `canRearrange(_:)` | 63–65 | `kind`, `sourceText` | — | `kind == .sentence && pieces.count > 1`. |
| `shuffledPieces(of:attempts:)` | 73–84 | `sourceText` | **yes** | ≤1 piece → unchanged. Up to 8 `shuffled()` draws, returning the first that differs from the ordered array; if all 8 match, returns `ordered.reversed()`. |
| `judgeArrangement(_:for:)` | 92–94 | `sourceText` | — | `judgeSentenceAnswer(pieces.joined(separator: " "), for: card)`. Compares the string, never positions. |
| `PieceTray` | 108–166 | — | — | UI state as a value: `place(from:before:)` (128–133, clamps target, ignores bad source), `takeBack(at:)` (140–143, appends to pool end), `move(from:before:)` (146–153, target decremented when past source), `static landing(movingFrom:before:)` (158–160), `produced`, `isEmpty`. Pinned by `Tests/PieceTrayTests.swift` (11 tests), a sixth test file outside the ticket's five. |
| `SentencePiece` | 179–186 | — | **yes** | `id = UUID()` per piece, so identical words are distinct for animation. Never read by judging. |

No settings and no clock.

### `Study/PracticeRound.swift` (152 lines, 70 of code)

| Rule | Lines | card | rand | Notes |
|---|---|---|---|---|
| `AnswerMode` | 25–34 | — | — | `.choosing`, `.typing`, `.rearranging`, `.translating`. `needsCloze` (130) is true for the first two. |
| `PracticeItem` | 43–66 | `id`, `translation` | **yes** | `token = UUID().uuidString` (49), generated **once when the item is built**, not per submission. `prompt` = `question?.prompt ?? card.translation` (52–54). `questionType` maps mode → `cloze_choice` / `cloze_typed` / `sentence_rearranged` / `sentence_typed` (58–65). |
| `askableModes(for:deck:)` | 144–152 | via `makeCloze`, `canRearrange` | indirect | Order built: `.choosing` if a cloze exists and `cloze.choices` is non-empty; `.typing` if a cloze exists; `.rearranging` if `canRearrange`; `.translating` always. Never empty. Calls `makeCloze` (which shuffles distractors) only to test emptiness. |
| `DeckSummary` | 73–95 | `kind`, `id`, `sourceText` | indirect | Entry-screen counts: `words`, `sentences`, `usableSentences` (sentence cards with a cloze), `availableBlanks` (**all** `deckWords` matches of usable sentences, including ones `coversEverything` would reject — line 92 does not apply that filter). `kind == nil` cards counted as neither. |
| `RoundOutcome` | 101–125 | — | — | `correct`, `wrong`, `graduated: Set<Int>`; `record(correct:cardID:state:)` inserts the id when `state == .review`, removes it otherwise. Needs the post-answer `state`. |

No settings and no clock.

### `Study/PracticeQueue.swift` (206 lines, 89 of code)

| Rule | Lines | card | set | clock | rand |
|---|---|---|---|---|---|
| `learnAheadWindow` | 26 | — | — | — | — |
| `QueueEmpty` | 33–38 | — | — | — | — |
| `trainableCards(in:)` | 45–47 | `state` | — | — | — |
| `introducedCount(in:on:)` | 54–56 | `introducedOn` | — | `day` string | — |
| `isInLearning(_:)` | 59–61 | `state` | — | — | — |
| `nextCard(from:settings:now:today:avoiding:)` | 77–112 | `id`, `state`, `dueAt`, `createdAt`, `introducedOn` | `newCardsPerDay` | `now`, `today` | — |
| `nextItem(...)` | 122–139 | + everything `askableModes`/`makeCloze` read | `newCardsPerDay` | `now`, `today` | **yes** |
| `nextTrainingItem(from:avoiding:)` | 148–163 | `id`, `state` | — | — | **yes** (card and mode) |
| `remainingCards(from:settings:now:today:)` | 185–206 | `state`, `dueAt`, `introducedOn` | `newCardsPerDay` | `now`, `today` | — |

`nextCard` in full: empty deck → `.deckIsEmpty`. `pick` (86–89) takes the first candidate whose id is not `lastCardID`, falling back to the first candidate when that leaves nothing. `dueNow` = `state != .new && dueAt <= now`, sorted by `dueAt` ascending (91–92). Order: (1) due learning/relearning, (2) due others (review), (3) if `newCardsPerDay - introducedCount(today) > 0`, `state == .new` cards sorted by `createdAt` ascending (96–103), (4) learning/relearning cards with `dueAt <= now + 20 min` sorted by `dueAt` (107–109), else `.dayIsDone`.

`nextItem` draws the mode with `askableModes(...).randomElement() ?? .translating` (132) — uniform over what the card supports — then calls `makeCloze` a second time when the mode needs one (135), which draws fresh distractors.

`remainingCards` = due-now count + `min(max(quota − introduced today, 0), new-card count)` + learning cards with `now < dueAt <= now + 20 min`. Invariant pinned by a test: `0` exactly when `nextCard` fails.

`nextTrainingItem` and `trainableCards` serve 永無止盡的訓練, which the map lists as out of scope.

### Randomness: every entry point, and whether a test can inject it

| # | Where | Call | Injectable? |
|---|---|---|---|
| 1 | `ClozeQuestion.swift:37` | `([answer] + distractors).shuffled()` on each read of `choices` | No |
| 2 | `ClozeQuestion.swift:118` | `pool.shuffled().prefix(count)` — which distractors | No |
| 3 | `SentenceAnswer.swift:77` | `ordered.shuffled()`, up to 8 times | No (`attempts` is a parameter; the generator is not) |
| 4 | `PracticeQueue.swift:132` | `askableModes(...).randomElement()` — the mode | No |
| 5 | `PracticeQueue.swift:155,157` | training card and mode | No |
| 6 | `PracticeRound.swift:49` | `UUID().uuidString` — idempotency token | No |
| 7 | `SentenceAnswer.swift:180` | `UUID()` per piece | No |

No function takes a `RandomNumberGenerator` or a `using:` argument; all use the system generator. The tests cope by asserting properties instead of outcomes: counts and set membership (`ClozeQuestionTests` 107–116, 191–200), a 50-iteration loop (`SentenceAnswerTests` 105–112), `nextCard` rather than `nextItem` for ordering, and decks arranged so only one outcome is possible (`PracticeQueueTests` 267–287).

### Clock: every entry point

The five files never read a clock; `now: Date` and `today: String` are parameters (`PracticeQueue.swift:11–14`). The view supplies them:

- `now` = `Date()` at `PracticeView.swift:302` and `:616`; also `:154` for the start screen's due count.
- `today` = `PracticeView.today()` (`:116–122`): Gregorian `yyyy-MM-dd`, `en_US_POSIX`, **device-local timezone, midnight boundary** — not the scheduler's 04:00 rollover (`Scheduler.swift:153`).
- The answer moment = `Date()` at `PracticeView.swift:535`, used for both the local schedule and the request.

### What the view does around the queue (`Study/PracticeView.swift`) — not ported, but it defines the queue's contract

- Loads `repository.cards()` then `repository.settings()`; a failed settings fetch silently leaves `StudySettings.fallback` = `[5, 7, 10]` / `15` (`:32`, `:138`; `Net/StudySettings.swift:31`).
- `answer(_:)` (`:532–563`): **before** the request, in scheduled mode, applies `nextSchedule(...)` from `Scheduler.swift` to the in-memory deck with `introducedOn: PracticeView.today()` (`:550–559`). Then fires `submit` without awaiting it.
- `submit` (`:580–604`): `recordReview(cardID, questionType, isCorrect, clientToken: item.token, localDate: moment, answeredAt: moment, context, elapsedMs: nil)`; on success `deck[index].apply(result)` overwrites the six scheduling fields (`Net/LearningCard.swift:198–205`); on failure the local move stands. Then `outcome.record(...)` with the card's current `state`.
- `advance()` (`:606–633`): sets `lastCardID`, calls `nextItem(from: deck, settings:, now: Date(), today:, avoiding: lastCardID)`; failure ends the session with the `QueueEmpty` reason. Then `seedPieces()` builds `PieceTray(available: shuffledPieces(of:))` for a rearrangement.
- Typed modes share one field: `item.question.map { judgeClozeAnswer(typed, for: $0) } ?? judgeSentenceAnswer(typed, for: item.card)` (`:403–406`); Check is disabled while the trimmed text is empty (`:409`).
- `choices` is read inside the view body (`:380`).

---

## 2. API fields depended on

`docs/api-contract.md` documents only the catalog and progress routes; it contains no mention of `/cards`, `/reviews` or `/study/settings`. The contract below is read from `backend/app/models.py` and `backend/app/main.py`. `web/src/api/types.ts` and `client.ts` contain nothing about cards; `client.ts` has `getJson` and a private `requestJson` (used by the `PUT` in `saveProgress`), which map 404 → `notFound`, 5xx → `unavailable`, other non-2xx (including 422) → `unexpected`.

### `GET /cards` → `LearningCardResponse[]` (`models.py:227–278`, `main.py:848–880`, `:915–925`)

Unpaginated; ordered `created_at DESC, id DESC` (`learning_card_store.py:138–150`). Timestamps are Python `isoformat()` in UTC: `2026-07-29T22:20:10.081902+00:00`, with the fraction **omitted when microseconds are zero**.

| JSON field | Type | Read by the logic? |
|---|---|---|
| `id` | int | Yes — exclusion, avoidance, choice judging, review URL |
| `sourceText` | string, unnormalised | Yes — every matching and judging rule |
| `translation` | string | Yes — prompt for rearrange and translate |
| `kind` | `"word"` \| `"sentence"` \| null (typed `Optional[str]`) | Yes — gates cloze and rearrange |
| `state` | `"new"` \| `"learning"` \| `"review"` \| `"relearning"` | Yes — queue |
| `ladderStage` | int 0–6 | Yes — which word a cloze removes |
| `introducedOn` | `"yyyy-MM-dd"` \| null | Yes — daily quota |
| `dueAt` | ISO-8601 UTC string | Yes — queue |
| `createdAt` | ISO-8601 UTC string | Yes — order of new cards |
| `learningStep`, `previousStage` | int \| null | Display only (`CardSchedule.swift`) and the local scheduler |
| `targetLanguage`, `comicId`, `chapterId`, `pageNumber`, `comicTitle`, `chapterTitle`, `lookupCount`, `lastLookedUpAt` | — | Not read by the five files |

Swift decoding is lenient in two places a port would otherwise not know about: an absent/unrecognised `kind` becomes `nil`, and an absent/unrecognised `state` becomes `.new` (`Net/LearningCard.swift:161–171`). The server's normalised key is deliberately not in the response (`LearningCard.swift:69–73`).

### `POST /cards/{id}/reviews` (`models.py:304–350`, `:368–395`; `main.py:1069–1128`)

Request body, with what iOS sends (`Net/APIStudyRepository.swift:173–181`):

| Field | Server validation | iOS value |
|---|---|---|
| `questionType` | `"cloze_choice"` \| `"cloze_typed"` \| `"sentence_rearranged"` \| `"sentence_typed"` | from `PracticeItem.questionType` |
| `isCorrect` | bool | `verdict.isCorrect` (`.correctApartFromTones` is sent as `true`) |
| `clientToken` | string, 1–100 chars, unique across all reviews | `UUID().uuidString` (upper-case `[ran]`), one per question |
| `localDate` | date, **required** | device-local `yyyy-MM-dd` of the answer moment |
| `answeredAt` | datetime, optional; naive read as UTC; absent → server now | `ISO8601DateFormatter().string(from:)`, e.g. `2026-10-12T13:53:58Z` — whole seconds `[ran]` |
| `context` | `"review"` \| `"training"`, default `"review"` | by session mode |
| `elapsedMs` | optional int ≥ 0 | always omitted (`nil`) |

Response `ReviewOutcome`: `review` `{ id, cardId, questionType, isCorrect, elapsedMs, reviewedAt }`, `state`, `learningStep`, `ladderStage`, `previousStage`, `introducedOn`, `dueAt`, `intervalChanged`. Swift ignores `review` (`Net/CardReview.swift:22–39`).

Behaviour `[read]`: 404 when the card does not exist. A replayed `clientToken` writes no row, moves nothing, and returns the card's **current** scheduling block. The docstring says a replay "answers 200", but the decorator is `status_code=201` and the handler takes no `Response` to change it (`main.py:1069–1070`) — not run. `introducedOn` is stamped from the request's `localDate` when a card leaves `new` (`card_review_store.py:174–178`). Day-length intervals use a server-configured timezone (`config.get_scheduling_timezone`), not anything in the request. A `review`-state card answered before `dueAt` is returned unchanged; **learning steps are deliberately not covered by that guard** (`scheduler.py:186–212`).

### `GET` / `PUT /study/settings` (`models.py:398–418`, `main.py:1037–1066`)

`{ "learningSteps": int[], "newCardsPerDay": int }` in both directions. `learningSteps` needs at least one entry, each > 0; `newCardsPerDay` ≥ 0. `GET` seeds defaults if unset. The five files read only `newCardsPerDay`; `learningSteps` is read by `scheduleState` (`CardSchedule.swift:21–36`, the "Learning 2/3" label) and by the local scheduler.

### Computed on the phone, not obtainable from the API

- The card's schedule **before the response arrives** — `nextSchedule` (`Scheduler.swift`), applied at `PracticeView.swift:550–559`. With no scheduler on the web, the deck is stale between tapping and the response.
- `today` and `now` (client clock and timezone), and the locally stamped `introducedOn`.
- `remainingCards`, `DeckSummary`, `RoundOutcome` — derived client-side; no endpoint returns them.
- Which cards a sentence contains, the distractors, the shuffles, the mode: all client-side by design.
- Queued answers and the deck snapshot (`PendingAnswerStore`, `knownCards()`): offline machinery with no web counterpart.

---

## 3. Cost per question type

Line counts are whole-file / code-only (comments and blanks excluded). The Swift files are roughly 55–60 % commentary.

**Shared by every mode**

| Piece | Swift | Lines (code) |
|---|---|---|
| `normalizedKey`, `toneInsensitiveKey` | `TextNormalization.swift:41–81` | ~12 |
| `TypedVerdict` | `ClozeQuestion.swift:145–155` | 6 |
| `AnswerMode`, `PracticeItem`, `questionType` mapping, `askableModes` | `PracticeRound.swift:25–66, 128–152` | ~35 |
| Card and settings types, review request/response types, three client calls | new on the web | — |

**Per mode**

| Mode | `questionType` | Card kinds it can ask | Needs, beyond the shared set | Approx. code lines |
|---|---|---|---|---|
| Cloze, four-choice (`.choosing`) | `cloze_choice` | `kind == "sentence"` only, containing ≥ 1 other card's text on a boundary without covering the whole line, **and** a deck with ≥ 3 plausible distractors | All of `DeckWordMatching.swift` (53); `makeCloze`, `coversEverything`, `distractors`, `pieceCount`, `isPlausibleOption`, `choices` (~45). Judged by id; no key needed for judging. 2 random draws. | ~100 |
| Cloze, typed (`.typing`) | `cloze_typed` | As above, minus the distractor requirement | All of `DeckWordMatching.swift` (53); `makeCloze`, `coversEverything` (~25; `makeCloze` calls `distractors` unconditionally); `judgeClozeAnswer` (~12). No randomness if distractors are skipped. | ~90 |
| Rearrange (`.rearranging`) | `sentence_rearranged` | `kind == "sentence"` with > 1 whitespace-separated piece | `sentencePieces`, `canRearrange`, `shuffledPieces`, `judgeArrangement`, `judgeSentenceAnswer` (~25); `punctuationInsensitiveKey` (5); `PieceTray` + `SentencePiece` (~35). 1 random draw. Does not need the deck. | ~65 |
| Translate (`.translating`) | `sentence_typed` | **Every** card: word, sentence, and `kind == null` | `judgeSentenceAnswer` (8); `punctuationInsensitiveKey` (5). No randomness, no deck. | ~13 |

**Overlaps.** The two cloze modes share `DeckWordMatching.swift` and `makeCloze` entirely; the second cloze mode costs ~12–25 lines after the first. Rearrange and translate share `judgeSentenceAnswer` and `punctuationInsensitiveKey`. The cloze pair and the sentence pair share only the keys and `TypedVerdict`.

**Coupling through `askableModes`.** It asks `makeCloze` whether a cloze exists in order to list the modes, and the mode is drawn uniformly from that list (`PracticeQueue.swift:132`). Word cards and `kind == null` cards always resolve to `[.translating]`; a sentence card with no deck word in it to `[.rearranging, .translating]`; a full sentence card to all four.

**The queue, independent of any mode.** `nextCard`, `remainingCards`, `introducedCount`, `isInLearning`, `learnAheadWindow`, `QueueEmpty`: ~55 code lines of `PracticeQueue.swift` (the remaining ~34 are `nextItem` and the training entrance). `RoundOutcome` is 17 code lines; `DeckSummary` is 18 and pulls in `makeCloze` and `deckWords`. The queue's inputs are the deck, `newCardsPerDay`, `now` and `today`; it is the only consumer of date parsing.

---

## 4. Normalisation parity

### How each key is computed

| Step | Swift (`TextNormalization.swift`) | Python (`normalization.py:35–42`) |
|---|---|---|
| 1 Normal form | `.precomposedStringWithCompatibilityMapping` (NFKC) | `unicodedata.normalize("NFKC", text)` |
| 2 Whitespace | `.filter { !$0.isWhitespace }` — per **grapheme**, decided by its first scalar's `White_Space` property | `not ch.isspace()` — per **code point** |
| 3 Case | `.lowercased()` — no locale argument | `.lower()` |
| Tone key | `đ`→`d`, NFD, drop U+0300–U+036F | *no Python counterpart* |
| Punctuation key | drop general categories P\* and S\* | *no Python counterpart* |

Only `normalizedKey` exists on both sides. The backend never judges an answer; it receives `isCorrect`. The shared vector table (`Tests/DeckLookupTests.swift`, `backend/tests/test_learning_cards.py`) covers half-width kana, case, spacing and Japanese; it contains **no Vietnamese vector**.

`đ`/`Đ`: step 3 lowercases `Đ` (U+0110) to `đ` (U+0111); only `toneInsensitiveKey` maps it to `d`, by explicit replacement, because `đ` has no canonical decomposition. The literal in the Swift source is U+0111 (bytes `c4 91`, checked with `xxd`). `normalizedKey` and `punctuationInsensitiveKey` keep `đ` distinct from `d`.

The tone key removes more than tones: horn and breve/circumflex are combining marks in the same block, so `ơ ô ở` → `o`, `ư` → `u`, `ă â` → `a`, `ê` → `e` `[ran]`.

### JavaScript equivalents tested

```
nk(s)    = s.normalize('NFKC').replace(/\p{White_Space}/gu, '').toLowerCase()
tone(s)  = nk(s).replaceAll('đ', 'd').normalize('NFD').replace(/[̀-ͯ]/g, '')
punct(s) = nk(s).replace(/[\p{P}\p{S}]/gu, '')
```

44 inputs were run through Swift, Python (`normalized_key` only) and these three functions, and compared scalar by scalar.

### Verified by running `[ran]`

**Vietnamese: identical everywhere.** All three keys matched Swift exactly, and `nk` matched Python, for every Vietnamese input: precomposed (`đạo luật`), fully combining (`đ a U+0323 o`), both orders of stacked marks (`a U+0323 U+0302` and `â U+0323` both → U+1EAD), upper/mixed case (`ĐẠO LUẬT`, `Đạo  Luật\n`, `KỶ LƯỠNG`), sentences with trailing `.` and `,`.

| Input | `nk` | `tone` | `punct` |
|---|---|---|---|
| `ĐẠO LUẬT` | `đạoluật` (0111 1EA1 006F 006C 0075 1EAD 0074) | `daoluat` | = `nk` |
| `THÂN THỂ` / `THÂN THÊ` | `thânthể` / `thânthê` (differ) | `thanthe` / `thanthe` (equal) | — |
| `xam pham` / `xâm phạm` | differ | equal | — |
| `hoà` / `hòa` (old / new tone placement) | differ (006F 00E0 vs 00F2 0061) | equal → `.correctApartFromTones` | — |
| `CHO BẢN THÂN.` | `chobảnthân.` | `chobanthan.` | `chobảnthân` |

Individual JS facts:

- `'hoà' === 'hoà'` is `false`; after `.normalize('NFC')` it is `true`. Swift `==` on the same pair is `true` without normalising — Swift `String` equality is canonical equivalence, JS `===` is code units.
- `'đĐ'.normalize('NFD')` → unchanged (0111 0110); NFKD likewise. `đ` never decomposes.
- `'ĐẬỞƯ'.toLowerCase()` → 0111 1EAD 1EDF 01B0, as Swift and Python.
- `'I'.toLocaleLowerCase('tr')` → `ı` (U+0131); `'I'.toLowerCase()` → `i`. `toLowerCase` is locale-independent; `toLocaleLowerCase` is not.
- `'d'.localeCompare('đ', 'en', {sensitivity:'base'})` → `0`, but with `'vi'` → `-1`; `'a'.localeCompare('á', 'vi', {sensitivity:'base'})` → `0`. Collator-based comparison is locale-dependent and matches none of the three keys.
- `/\p{M}/gu` in place of `[̀-ͯ]` gives the same result for Vietnamese but **differs for Japanese**: `が` → Swift tone key `か U+3099`, `\p{M}` version `か`.

**Where the candidates differed from Swift** (none involves Vietnamese letters):

| Input | Swift `nk` | Python `nk` | JS `nk` (`\p{White_Space}`) | JS with `\s` |
|---|---|---|---|---|
| `a U+0085 b` (NEL) | `ab` | `ab` | `ab` | **`a U+0085 b`** |
| `a U+FEFF b` (BOM) | kept | kept | kept | **`ab`** |
| `a U+001C b` | kept | **`ab`** | kept | kept |
| `a´b` (U+00B4) and `a␠U+0301 b` | **`ab`** | `a U+0301 b` | `a U+0301 b` | `a U+0301 b` |
| `ΟΔΟΣ` (final sigma) | `οδοσ` (03C3) | `οδος` (03C2) | `οδος` (03C2) | same |
| `ﾀﾞｲｼﾞｮｳﾌﾞ` | **30BF 3099 …** (not recomposed) | 30C0 … | 30C0 … | same |

- U+00A0, U+3000, U+2028 are removed by all; U+200B is kept by all.
- The U+00B4 row is an existing **Swift-versus-Python** difference: NFKC turns `´` into space + U+0301, which Swift drops as one whitespace grapheme and Python keeps as a stray combining mark.
- The kana row: on this machine Foundation's NFKC left `タ` + U+3099 uncomposed (while `precomposedStringWithCanonicalMapping` composed it to U+30C0). The shared-vector test still passes in Swift because `"ダ" == "タ\u{3099}"` is `true` there.
- `punct` using `[\p{P}\p{S}]` matched Swift's `punctuationCharacters ∪ symbols` on every input, including curly quotes, `– … $ + = ^ ~ `` ` `` ¿ 。、！ © ® ° ⁄ _ - ' ’` and an emoji (all removed), apart from the rows above inherited from `nk`.

**Other JS behaviour checked `[ran]`:**

- `Date.parse('2026-07-29T22:20:10.081902+00:00')` → `1785363610081` (microseconds truncated to ms); the fraction-less form parses too. Swift's fractional `ISO8601DateFormatter` gives `1785363610.081` for the same string — same precision.
- Under `TZ=Asia/Taipei` at `2026-10-12T17:30:00Z`: `toISOString().slice(0,10)` → `2026-10-12`; local `getFullYear/getMonth/getDate` → `2026-10-13`.
- `crypto.randomUUID()` is lower-case; `UUID().uuidString` upper-case. The server accepts any 1–100 character string.
- `Array.prototype.sort` kept ties in input order; Swift `sorted` did as well.
- `/\bÀO\b/.test('CHÀO')` → `true` with or without the `u` flag (`\b` is ASCII-only). A lookaround on `[\p{Alphabetic}\p{N}]` gives `false` for `CHÀO` and `true` for `XIN ÀO.`.
- `Character.isLetter` / `isNumber` against JS classes: U+24D0 `ⓐ` is `isLetter` and `\p{Alphabetic}` but not `\p{L}`; `①` and `²` are `isNumber` and `\p{N}`; `一` is `isNumber` (numeric type) but not `\p{N}` — it is a letter either way. `_` is neither, in both.
- A sentence stored in NFD: `'THÂN THỂ'.normalize('NFD')` is 11 code units but 8 graphemes. NFKC applied per code unit leaves it decomposed (`A U+0302`, `E U+0302 U+0309`); applied per `Intl.Segmenter` grapheme it yields `Â`, `Ể` as Swift's per-`Character` loop does.
- `'\u0085a﻿'.trim()` → `U+0085 a` (trims BOM, keeps NEL); Swift `.trimmingCharacters(in: .whitespacesAndNewlines)` → `a U+FEFF` (the reverse), and it also trims U+200B, which JS `trim()` does not.
- `'não'.indexOf('na')` → `0`; Swift `range(of:)` on the same pair → `nil` (it will not match inside a grapheme).

### Inferred, not run `[read]`

- That iOS Foundation behaves as macOS Foundation did here (NFKC kana, whitespace-grapheme rule, sigma).
- That browsers match Node: `String.prototype.normalize`, `toLowerCase` and `\p{…}` are specified by ECMAScript, but the Unicode version varies by engine. Python in the backend image is 3.12 (`backend/Dockerfile:3`), not the 3.10 used here.
- What a macOS Vietnamese input method emits (precomposed or combining; old or new tone placement) could not be determined from a terminal. Any NFC/NFD difference is absorbed by step 1 of every key; old/new tone placement is absorbed only by the tone key, so it grades as `.correctApartFromTones` rather than `.correct`.

---

## 5. Test inventory

All use Swift Testing (`@Test`). Fixtures are built with `LearningCard.preview(...)` (`Study/StudyView.swift:263`), which decodes JSON; the web needs its own card builder.

| File | `@Test` | Code lines | What it pins |
|---|---|---|---|
| `ClozeQuestionTests.swift` | 23 | 163 | **Building (7):** deck word → question; least-familiar chosen; tie on position; no deck word → nil; word card → nil; `kind == nil` → nil; never blanks itself. **Distractors (9):** from other cards, no repeats; never normalisation-equal to the answer; no whole sentence as an option; all-sentence deck → no choices; one-syllable answer still has a pool; piece counting; too few → none; no distractors → no choices; answer is among four choices. **Typed judging (7):** right word; case and spacing; missing tone → `.correctApartFromTones`; exact → `.correct`; leniency does not reach matching; different word; empty → wrong. |
| `DeckWordMatchingTests.swift` | 14 | 96 | **Matching (12):** found and blanked intact; case; doubled spaces and line breaks with the blank landing right; full-width forms; no match inside a longer word; different tone ≠ match; found twice; none; empty-key card; order of appearance; start/end boundary; punctuation as boundary. **Real deck (2):** three real sentences yield exactly the expected blanks; an OCR tone slip yields none. |
| `SentenceAnswerTests.swift` | 16 | 98 | **Judging (7):** exact; case/spacing/punctuation; missing tone named; wrong order wrong; different word; empty; word card through the same function. **Rearranging (9):** pieces are the words; whitespace split; shuffle never in order (50 iterations); correct assembly; other order wrong; repeated word either way; word card not rearranged; one-word sentence not rearranged; identical pieces terminate. |
| `PracticeQueueTests.swift` | 29 | 264 | **Order (7):** learning before review; relearning counts as learning; due before new; longest-waiting first; new in collection order; no immediate repeat; one-card deck repeats. **Quota (4).** **Learn-ahead (4):** 3 min offered; not while something is due; 40 min never; learning only. **Session end (2):** empty deck vs day done. **Training pool (5):** out-of-scope entrance. **Remaining (7):** zero ⇔ queue empty across seven decks; quota caps; no double count; introducing leaves the count; wrong stays, graduated leaves. Fixed clock `1_756_600_000`, `today = "2026-08-31"`. |
| `PracticeRoundTests.swift` | 17 (one parameterised ×3 → 19 cases) | 156 | **Askable modes (6):** word card → translate only; word card never cloze at slots 0/2/6; sentence without a deck word → `[.rearranging, .translating]`; full sentence → all four in order; slot changes nothing; never empty (including a blank-text card). **Round outcome (6).** **Deck summary (5).** |

Total: 99 `@Test` functions, 777 code lines. Adjacent and not in the five: `PieceTrayTests.swift` (11 tests, 86 code lines) for `PieceTray`; the shared normalisation vectors in `DeckLookupTests.swift`. There is no Swift test file dedicated to `toneInsensitiveKey` or `punctuationInsensitiveKey`; they are pinned only through the judging tests. 5 of the 29 queue tests cover the training entrance.

---

## 6. Places a port can silently disagree

Ranked by how likely the specific code is to be re-expressed differently and how invisible the result would be.

1. **The deck is stale until the review response lands.** iOS moves the card locally before posting (`PracticeView.swift:550–559`) and builds the next question without awaiting the response (`:562`, `:606`). A port with no scheduler that calls `nextCard` before the response has been applied sees the answered card as still due; `avoiding` hides it for one question only (`PracticeQueue.swift:86–89`). The server's early-answer guard covers `review` cards but not learning steps (`scheduler.py:207–212`).
2. **`today` computed in UTC.** Quota and `introducedOn` use the device-local calendar day (`PracticeView.swift:116–122`, `APIStudyRepository.swift:177, 194–200`); `localDate` is required by the server and becomes `introducedOn`. `toISOString()` yields the UTC day — a different date from 00:00 to 08:00 in Taipei `[ran]`. The two clients share the quota only if they produce the same string.
3. **Word boundaries.** `isOnABoundary` (`DeckWordMatching.swift:97–104`) uses Unicode `isLetter`/`isNumber`. JS `\b` and `\w` are ASCII-only, so `ÀO` matches inside `CHÀO` `[ran]`.
4. **Offsets in the origin map.** `normalizedWithOrigins` (`DeckWordMatching.swift:38–51`) works per grapheme and maps hits back to grapheme indices; `blanking` and `removed` depend on those ranges (`ClozeQuestion.swift:77–78`). Indexing by UTF-16 code unit agrees only while `sourceText` is NFC and in the BMP; on NFD text the key itself differs `[ran]`.
5. **Whitespace class.** `Character.isWhitespace` is used in five places — `TextNormalization.swift:46`, `DeckWordMatching.swift:44`, `ClozeQuestion.swift:127`, `SentenceAnswer.swift:54`, plus the different set `.whitespacesAndNewlines` at `ClozeQuestion.swift:92`. `\s` disagrees on U+0085 and U+FEFF; `trim()` disagrees on U+0085, U+FEFF and U+200B `[ran]`.
6. **Tie-breaking depends on deck order and stable sorts.** `dueNow` and `soon` sort by `dueAt` only, `fresh` by `createdAt` only (`PracticeQueue.swift:92, 101, 108`); `makeCloze` takes the first minimum (`ClozeQuestion.swift:69–72`) over matches sorted only by start (`DeckWordMatching.swift:93`). Ties resolve to `GET /cards` order (newest first), so cards with equal `createdAt` are offered highest id first, and two cards starting at the same position (`ĐẠO` and `ĐẠO LUẬT`) at the same `ladderStage` resolve by deck order. Re-sorting or indexing the deck by id changes outcomes.
7. **Two judging rules, not one.** Cloze typing compares `normalizedKey`, which keeps punctuation (`ClozeQuestion.swift:169–179`); sentence judging strips it (`SentenceAnswer.swift:35–42`). The view picks between them by whether `question` is nil (`PracticeView.swift:403–406`).
8. **Tone stripping range.** U+0300–U+036F exactly (`TextNormalization.swift:79`); `\p{M}` is wider and changes Japanese keys `[ran]`. The `đ` replacement must come before NFD and after lowercasing (`:75–77`).
9. **String equality on un-normalised text.** `candidate != ordered` in `shuffledPieces` (`SentenceAnswer.swift:78`) and every Swift `==` treat canonically equivalent strings as equal `[ran]`; `===` does not. Comparisons that go through a key on both sides are unaffected.
10. **Lenient decoding.** `kind` null/unknown → no cloze, no rearrange, translate only; `state` unknown → treated as `new` (`LearningCard.swift:161–171`). A strict TypeScript union would reject or mis-route such cards.
11. **`choices` reshuffles on every read** (`ClozeQuestion.swift:36–38`), although its comment says "stable shuffled order", and the view reads it in `body` (`PracticeView.swift:380`). `askableModes` also reads it just to test emptiness (`PracticeRound.swift:147`), and `nextItem` rebuilds the cloze (`PracticeQueue.swift:135`), so the distractors of the question shown are a second draw.
12. **The distractor pool is the whole deck** (`ClozeQuestion.swift:109–116`), including the sentence card being asked and cards of any `kind` or `targetLanguage`, limited only by piece count; whereas the *match* deck excludes the sentence card (`:66`).
13. **One token per question, not per request** (`PracticeRound.swift:49`). A token minted at submit time makes a retry a second answer.
14. **`DeckSummary.availableBlanks` counts matches `makeCloze` would reject** (`PracticeRound.swift:90–93` omits the `coversEverything` filter of `ClozeQuestion.swift:68`).
15. **Mode distribution.** Uniform over `askableModes` (`PracticeQueue.swift:132`); the share of each mode on the web follows from how many modes exist there.

---

## 7. Open questions

- **Is every stored `sourceText` NFC?** The database was not inspected. Hazards 4 and 9 are live only if some card is stored decomposed (Vision OCR output and hand corrections on iOS are the two sources).
- **What does a macOS Vietnamese input method emit** — precomposed or combining, old or new tone placement? Not determinable here; see [issue 04](../issues/04-typing-vietnamese-at-a-desk.md).
- **Does iOS Foundation reproduce the macOS results** for NFKC of half-width kana, whitespace graphemes and sigma? Only macOS was run.
- **Replay status code.** The docstring of `record_review` says 200; the code as read returns 201. Not exercised.
- **Is `choices` reshuffling on re-render visible on a device**, or does SwiftUI happen not to re-evaluate the body between appearing and tapping? Not observed.
- **Swift `sorted` stability** was observed, and hazard 6 relies on it, but it was not confirmed as a documented guarantee.
- **Unicode-version drift** between browser engines, Python 3.12 in the backend image, and iOS for `White_Space`, P\*/S\* and case mappings was not measured; the 44 inputs agreed across Unicode 13 (Python), 17 (Node) and the macOS tables.
- **The settings fallback.** iOS silently uses `[5, 7, 10]` / `15` when `GET /study/settings` fails; whether the web should have any fallback is undecided and not answerable from the code.
- **No authoritative API document exists for the card routes**; `docs/api-contract.md` stops at reading progress, so section 2 rests on the Python source alone.
