Status: ready-for-agent

# Vocabulary review: turning what you looked up into something you come back for

This is a **PRD, not a spec**. Its scope spans five stages and is deliberately too large to
execute as one spec. Each stage becomes its own spec under this folder (see *Cutting this
into specs*), and no stage's spec is finalised until the previous one has actually shipped
and been used.

`Status: draft-prd` is a deliberate new value alongside the existing `ready-for-agent` and
`parked`. It marks a concept-stage document that has been argued through but is not yet
executable, and is intended for reuse whenever a new feature starts this way.

## Problem Statement

Reading and comprehension are done. M1–M10 are complete and offline download merged in full
on 2026-08-18. What is not done — and has now failed twice — is turning a lookup into
learning.

**Both previous attempts failed the same way, and neither failed because of its content.**

The 單字本 (saved vocabulary) tab was deleted by commit `8af068e` on 2026-08-06, removing
4,174 lines. The decision is on the record: `.scratch/comprehension-response-ux/spec.md:276`
lists as Out of Scope "**單字本 as a study or review feature** — spaced repetition, quizzing,
curation. The tab is being removed, not improved", and `map.md:44` states the premise: "The
developer confirmed saved vocabulary is rarely revisited, which is the premise for replacing
it with an automatic history."

History was that replacement. The developer does not use it either.

The developer's own diagnosis: both features arrived early, as something bolted on alongside
the comic reader — "順便一起進來的" — never thought through on their own terms, and with
nothing that ever asked him to come back. Reading a comic is not a moment at which anyone
wants to browse what they read last week.

**What is different this time** is not a better list. It is that the motivation is now
explicit and specific: the developer wants to read these comics in the original language, and
wants the reward to be the one this app is uniquely able to give — *recognising a word on the
page and not needing to look it up*. Anki does not know you met the word in real life.
Duolingo does not either. This app does, because the lookup happens inside it.

### Scope boundary

A longer-term product concept exists in `log/20260819.md` (Chrome extension capture, account
sync, multi-language profiles, B2B learning engine, paid tiers). **None of that is in this
PRD.** Only its §6–§13 material — daily lesson, memory model, question types — is used as
input. This PRD is confined to the vista_comic iOS app, one user, no accounts, and exists so
the developer can find out whether this works for him before anything larger is built on it.

## Settled decisions

| Decision | Outcome |
|---|---|
| Scope | Inside vista_comic. One iOS app. No accounts, no extension, no language profiles |
| How cards enter the deck | **Manual.** Tapping "add" *is* the quality gate — it means the reader has read the source text and the translation and judged them right |
| Collection entry point | OCR -> correct -> Translate -> "Add to vocabulary" appears beside the translation result |
| Card atom | The text the reader selected and corrected, **and which of the two it is**: two save buttons, 加入單字 and 加入句子. The reader knows instantly what a tokeniser would have to guess at, and the answer decides which questions stage 3 asks and whether stage 4 generates a sentence for it (stage 1 ticket 06, added 2026-08-19) |
| Source location | `comicID` / `chapterID` / `pageNumber` only, matching the existing peek route. **No crop rectangle** |
| Scheduling | Fixed-interval ladder: 1 / 3 / 7 / 21 / 60 days. Correct advances one rung, wrong drops to the first. Correctness only — no speed or hint signals |
| Review log | Recorded in full (timestamp, question type, correct, elapsed ms) so swapping in FSRS later is an algorithm change, not a data migration |
| Question types | Matching pairs; sentence cloze; sentence translation; typing. **Where each one lives changed on 2026-08-20** — see *The lesson architecture* |
| Practice sentence corpus | Context comes from a user-authored `introduction.txt` in each comic folder (3,000 characters max; on launch the app tells the reader which comics are missing one) |
| Practice sentence budget | **5–10 sentences per day in total**, not one per card. The budget is allocated by familiarity and card age: low rungs and recently added cards weigh more. Generation keeps running on days when nothing is collected, and pauses only after **seven consecutive days with no new card**, resuming on the next one. The stock balances itself out over time |
| Cloze target | The blank is always a word that is in the deck. Generated sentences necessarily contain words that are not, and those are never blanked. Where several deck words appear in one sentence, blank the least familiar |
| Reading feedback | After OCR (when online), match against the deck. On a hit: mark "already learned", still show the meaning, increment `lookup_count`, and reschedule the card to the near term. **The negative is never inferred** — not looking a word up again is not evidence of knowing it |
| Game layer | Daily streak + daily completion; per-comic mastery progress; XP and levels. No ability scores |
| History tab | Removed in **stage 2**, alongside the tab that replaces it (moved from stage 5, 2026-08-19) |
| Archiving a card | **Not built.** A word on the ladder's top rung is already scheduled once every 60 days, which is what "I know this, stop testing me" would have meant. `archived_at` stays unused |
| Offline | Stages 1–5 are online-only. Offline review is deferred to a later "download pack" approach |

### Why the source text is trustworthy and the translation is not

`CroppedSelectionPreview.swift:155` binds a `TextEditor` to `editedText`, and both the
translation (`:502`) and the deep explanation (`:518`) are sent the corrected text. The reader
has therefore already fixed the OCR before anything else happens, so **the source string is
reliable**. The translation is not — which is why adding a card is a manual act. A deck built
automatically from output the reader does not trust would use spaced repetition to *reinforce*
errors, which is worse than no deck at all.

### Accepted cost of removing History

Once History is gone, a deep explanation that fails after the sheet is dismissed cannot be
retried — `ComprehensionDetailView` is the only retry path outside the sheet. This is accepted:
re-selecting the line and asking again costs one of 300 daily requests.

### Explicitly excluded

RAG / vector database — the whole context is a few hundred tokens and fits in the prompt, and
RAG organises a corpus you already have rather than obtaining one. Scraping comic dialogue —
conflicts with `log/20260819.md` §14 and is unavailable for most works. External work-metadata
APIs — replaced by `introduction.txt`. FSRS. Approximate-answer judging. Image-prompt question
types. Monsters, stages and badges. Free-form AI tutoring.

## Existing facts the implementation rests on

- "Translate" is on-device Apple Translation: no network, no record (`SelectionActions.swift`).
  Only "Explain in depth" performs `POST /comprehensions`.
- `comprehension_client.py` forces a tool with four string fields; the vocabulary breakdown is
  prose inside `grammarNotes`. Stage 4 is where that changes.
- The backend owns all durable state. `progress` (PK `comic_id, chapter_id`) proves per-comic
  rows can be stored while the catalog itself stays unpersisted (ADR-0001) via stable path-hash
  IDs (ADR-0003).
- `scanner.py` already reads a special file at a comic root (`_is_cover` / `_resolve_cover`
  finding `cover.*`). `introduction.txt` is the same shape of convention and does not violate
  the module's "NEVER writes" constraint.
- `comprehension_worker.py` is an existing queue worker (claim -> call Claude -> fill in).
  Practice-sentence generation reuses it. **No cron is needed.**
- `comprehend_usage_store.py:34` sets `DAILY_CAP = 300`; personal use will not reach it.
- iOS has no SwiftData/CoreData. `PendingProgressStore` is the existing offline catch-up queue
  pattern, for whenever offline review is taken up.

## Data model

New tables follow the `comprehension_record` template exactly: SQLAlchemy model in
`backend/app/db.py`, an Alembic revision on top of `4085885413a9`, a `*_store.py` module of
plain session-taking functions, camelCase Pydantic models in `models.py`, routes in `main.py`.

- **`learning_card`** — `id`, `source_text`, `translation`, `target_language`, `comic_id`,
  `chapter_id`, `page_number`, `comprehension_record_id` (nullable FK), `ladder_stage` (0–4),
  `due_on`, `lookup_count`, `created_at`, `archived_at`
- **`card_review`** — `id`, `card_id`, `reviewed_at`, `question_type`, `is_correct`, `elapsed_ms`
- **`practice_sentence`** (stage 4) — `id`, `card_id`, `sentence`, `sentence_translation`,
  `deck_spans` (JSON: every deck word the generator found in this sentence, each with its
  `card_id`, offset and length), `generated_at`, `model`

  *Spans, not a single target*: which word gets blanked depends on familiarity, and familiarity
  changes after the sentence is generated. Recording every deck word in the sentence lets the
  blank be chosen at question time rather than frozen at generation time.
- **`daily_completion`** (stage 5) — `completed_on` (PK), `questions_answered`, `completed_at`

No `user_id`: there is no identity to key on. No `comic_context` table: the context lives on
disk in `introduction.txt`, unpersisted like the rest of the catalog.

On iOS, each stage adds a `Decodable` model plus a `StudyRepository` protocol and
`APIStudyRepository`, injected through an `EnvironmentKey` — the shape of
`ComprehensionRepository.swift` / `APIComprehensionRepository.swift`. Testable actions are free
functions, as in `HistoryActions.swift`.

## The lesson architecture

Settled 2026-08-20, after stage 2 shipped, and **materially different from what the stage list
below originally said**. It came out of asking how a lesson actually runs, and the answer turned
out to have three separate places rather than one.

```
每日關卡  ── the ladder lives here, and only here
├── 克漏字        → moves the ladder
├── 翻牌          → does NOT move the ladder
└── 句子翻譯      → moves the ladder

錯題區            → outside the ladder entirely
單字練習          → outside the ladder entirely
├── 翻牌
└── 打字
```

**Matching sits inside the daily level without counting.** It is there to remind the reader of
the words between the two demanding question types — a warm-up, not an assessment. Selection for
it, and for both areas outside, is by familiarity and how often a word has come up recently
rather than by anything the ladder knows.

### Two clocks, deliberately

**The ladder moves at most once per day per card**, up or down, and what moves it is whether the
card reached 通過 in that day's level — not any individual answer.

Within a day a card climbs its own three-step ladder, which resets daily:

| Now | Correct → | Wrong → |
|---|---|---|
| first appearance | **熟悉** (skips 不熟) | 不熟 |
| 不熟 | 熟悉 | 不熟 |
| 熟悉 | **通過** | 不熟 |

So a card needs **two correct answers in a row to pass for the day**, and a round of five
questions is not five distinct words — a word appears until it passes or the round ends.

### 錯題區 is its own thing, and is allowed to grow

A wrong answer anywhere puts a card here. Answering it correctly first try removes it; anything
else leaves it. **It does not touch the ladder in either direction**, and letting it pile up is
normal rather than a failure state — the developer's call, following how Duolingo separates
practice from progress.

### The selection problem this creates

Weighting purely by familiarity deadlocks: the least familiar card always wins, so the same word
appears over and over while others never come up, and getting it wrong makes it more likely
still. Every list outside the ladder therefore needs **recent appearances to suppress weight** as
well as unfamiliarity to raise it. Named here because it is one rule shared by three places.

## Stages

### 1. Store the word
Backend: `learning_card` table and store; `POST/GET/DELETE /cards`; `POST /cards/lookup`, which
takes recognised OCR text, reports whether it is already in the deck, and on a hit increments
`lookup_count` and pulls `due_on` back to the near term.

iOS: "Add to vocabulary" beside the translation result in `CroppedSelectionPreview.swift`; a
lookup call after OCR completes, showing an "already learned" marker on a hit while still
displaying the meaning.

*The lookup path is in stage 1 because stage 2 displays a lookup count, and nothing else
increments it.*

### 2. Vocabulary library screen
A new tab under `Features/Study/` with its own `NavigationStack`. Lists source text,
translation, source comic, familiarity (ladder rung) and lookup count. Delete, archive, and
jump back to the page via the existing peek route.

### 3. Word breakdown
Backend: extend the `comprehension_client.py` forced tool with a structured `vocabulary` array
(surface form, reading, meaning in this context, part of speech, span in the source sentence).
The ripple runs DB -> Pydantic -> Swift `Decodable` -> UI, and it is the largest single piece of
backend work in this PRD.

Nothing is playable when this lands, which is the cost of doing it first. Everything after it
depends on a sentence knowing which words it is made of: cloze cannot choose a blank without it,
and generated practice sentences cannot be checked against the word they were written for.

### 4. The daily level
Backend: `card_review`, the ladder, the three-step day, and the endpoints a level runs on.

iOS: 每日關卡 — cloze, then matching as a warm-up between, then sentence translation. A card
passes the day by reaching 通過; the ladder moves at most once per day on that outcome, never on
a single answer. Matching never moves it at all.

`introduction.txt` and practice-sentence generation belong here too: cloze on a **word** card
needs a sentence containing that word, and only a **sentence** card already has one.

### 5. Practice areas
錯題區 and 單字練習, both outside the ladder and both selecting by familiarity suppressed by
recent appearances. 單字練習 holds words only, as matching and typing.

### 6. Game layer
`daily_completion`, streak, XP and levels. Per-comic mastery — how many words collected from
this comic, how many have reached a stable rung, how many were hit while reading this week — is
**optional and the lowest priority in this PRD**; drop it if the stage runs long.

Removing `Features/History/` **moved to stage 2** (2026-08-19), and shipped there.

## Verification

Per `CLAUDE.md`:

- Inspect the git diff each increment and confirm unrelated work is untouched.
- Backend: pytest over stores and routes, following the existing `comprehension_store` tests.
  Ladder advancement, lookup-hit rescheduling, distractor selection, the daily generation budget
  split, and cloze target selection are pure functions and must be unit tested.
- iOS: logic tests in `vista_comicTests`. **No XCUITest is written, built, or run.** UI
  verification is handed to the developer as a specific checklist per stage — one compact and
  one larger phone layout, plus empty, loading, failure and offline states.
- The five-minute test budget and single-kill rule in `CLAUDE.md` §5 apply unchanged.

### End-to-end check after stage 1
1. Open a comic, select a region, correct the OCR, tap Translate, tap "Add to vocabulary".
2. `GET /cards` shows the card with correct `comic_id` / `chapter_id` / `page_number`.
3. Select the same text again: the sheet shows "already learned", `lookup_count` has increased,
   and `due_on` has moved back to the near term.

## Cutting this into specs

Each stage is its own folder under `.scratch/vocabulary-review/`, holding a `spec.md` and its own
`issues/` — the shape the rest of the repo already uses.

| Folder | Contents | Depends on |
|---|---|---|
| `01-card-storage/` | `learning_card`, `/cards` endpoints, add button, offline queue, local deck snapshot and lookup marker | — |
| `02-card-library/` | Vocabulary tab: grouped list, search, edit the translation, delete, peek — **and the removal of 歷史紀錄** | 01 |
| `03-cloze-round/` | Deck-word matching, cloze questions, and a round that can be played. No ladder yet | 02 |
| `04-the-ladder/` | The ladder and the three-step day turn a round into 每日關卡 | 03 |
| `05-sentence-translation/` | The second question type, typed and rearranged, and how it is judged | 04 |
| `06-practice-sentences/` | Generation, so a **word** card can carry a cloze too | 05 |
| `07-practice-areas/` | 錯題區 and 單字練習, both outside the ladder | 04 |
| `08-game-layer/` | Streak, XP and levels, per-comic mastery (optional) | 04 |

**Reordered twice on 2026-08-20.** First, once the lesson architecture above was settled: what
had been stage 3 — matching plus the ladder — turned out not to be buildable first, because
matching is the one question type that deliberately does not count, and cloze is what the ladder
responds to.

Then again, after a spike. Cloze had been blocked on an LLM breakdown of each sentence into
words, scheduled two stages later. **It turned out not to need one**: the blank in a cloze is
always a word the reader has collected, so finding it is a search against a deck we already hold
rather than tokenisation. That removed a whole stage and moved a large piece of LLM work
(`06-practice-sentences/`) to the end, where the developer put it — the deck's own sentence cards
carry real sentences already, so generation buys variety rather than viability.

### Answer modes, settled 2026-08-20

| Question | How it is answered |
|---|---|
| Cloze | Four choices, or typed |
| Sentence translation | Typed, or rearranged from scrambled words |
| Matching | Tap to pair |

Sentence translation runs **Chinese → Vietnamese**: producing the target language is the harder
and more valuable direction, and the developer types Vietnamese comfortably. Judging strips
punctuation and whitespace and then requires an exact match, so word order and spelling — tones
included — must be right. That reuses the deck's existing normalisation rather than inventing a
second idea of "the same text".

Each spec is finalised only after the previous stage has shipped and been used, so its details
come from real experience rather than guesses about experience that has not happened yet.
