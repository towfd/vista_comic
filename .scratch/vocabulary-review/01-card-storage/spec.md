Status: ready-for-agent

# Vocabulary stage 1: collecting a word you have already confirmed

Stage 1 of `.scratch/vocabulary-review/prd.md`. Read the PRD first — the decisions it settles
(manual add as the quality gate, no accounts, no LLM in this stage) are not re-argued here.

## Problem Statement

There is no deck. Every stage after this one reviews, schedules, generates for and scores a
collection of cards that does not yet exist, so nothing else can start.

Today a selection leaves nothing behind unless the reader spends a request on a deep
explanation. `CroppedSelectionPreview.swift:66` says so explicitly about the corrected text:

> User-editable text, seeded from a successful recognition. Purely for on-screen
> display/correction — **never written anywhere**.

That comment stops being true in this stage, and must be updated with it.

The reader also needs one thing back immediately, before any review screen exists: when they
select a line they have already collected, the app should say so. That is the smallest version
of the reward the whole PRD is built around, and it costs almost nothing here because the deck
is small enough to keep on the phone.

## Solution

1. A card table on the backend, with create and list endpoints.
2. An **Add to vocabulary** button beside the translation result in the selection sheet.
3. A local snapshot of the deck, so "already collected" can be answered instantly and **offline**.
4. A pending-card queue, so collecting works with no network — which is when the reader is
   reading downloaded chapters and looking up the most words.

## User Stories

- As a reader, after correcting the OCR and tapping Translate, I can add that line to my
  vocabulary in one tap, without leaving the page I am reading.
- As a reader on a train with no signal, I can still collect words; they arrive on the server
  the next time the app has a connection.
- As a reader, when I select a line I have collected before, the sheet tells me I have already
  learned it — and still shows me the meaning, because I clearly did not remember it.
- As a reader, whatever translation I was looking at when I tapped add is what the card keeps.
  Nothing replaces it later behind my back.

## Implementation Decisions

### Card identity is a normalised key, and it is global

Two collected lines are the same card when their **normalised source text** and **target
language** match. The comic they came from is not part of the identity: the same word met in a
different work is the same word, and splitting it would fragment the lookup count that later
stages read as a forgetting signal.

The normalisation is defined here and implemented **twice** — Swift for the local match, Python
for the server's uniqueness constraint. The two must agree, so the rules are exhaustive and the
test vectors below are shared verbatim by both suites.

1. Unicode **NFKC** (folds full-width forms onto half-width).
2. Remove **all** whitespace, including newlines and ideographic space.
3. Lowercase.

Removing whitespace matters most for Japanese: OCR carries the speech-bubble line breaks into
the text, and `大丈夫\nですか` must be the same card as `大丈夫ですか`.

**Shared test vectors** (input -> key):

| Input | Key |
|---|---|
| `大丈夫\nですか` | `大丈夫ですか` |
| `　大丈夫ですか　` | `大丈夫ですか` |
| `ﾀﾞｲｼﾞｮｳﾌﾞ` | `ダイジョウブ` |
| `Good  Morning` | `goodmorning` |
| `good morning` | `goodmorning` |
| `食べた` | `食べた` |
| `食べる` | `食べる` |
| `   ` | *(empty — rejected)* |

The last two are deliberate: `食べた` and `食べる` are **different cards**. Merging inflected forms
needs a tokeniser, which the PRD excludes — but keeping them apart is also right on its own terms,
not merely cheaper. A form the reader can already read never gets collected again. A form that
keeps coming back is one they keep failing to read, and that repetition is precisely the signal
that it matters. Separate cards let the signal through per form instead of averaging it away.

### What a card stores

`learning_card`, an Alembic revision on top of `4085885413a9`, following the
`comprehension_record` shape (model in `db.py`, plain-function store in `learning_card_store.py`,
camelCase Pydantic in `models.py`, routes in `main.py`):

| Column | Notes |
|---|---|
| `id` | |
| `source_text` | exactly what the reader corrected, unnormalised — this is what gets displayed |
| `normalized_key` | derived; unique together with `target_language` |
| `translation` | **whatever was on screen when add was tapped** (see below) |
| `target_language` | |
| `comic_id`, `chapter_id`, `page_number` | first encounter only; matches the existing peek route's inputs |
| `comprehension_record_id` | nullable FK, always null in this stage |
| `ladder_stage` | 0 |
| `due_on` | the creation date |
| `lookup_count` | 0 |
| `last_looked_up_at` | nullable |
| `created_at`, `archived_at` | `archived_at` always null in this stage |

`ladder_stage` and `due_on` are written now and **given meaning in stage 3**. Nothing in this
stage reads them.

`source_text` is capped at 200 characters. This is a guard against a stray whole-page selection
becoming a card, not a feature.

### The translation is whichever one the reader was looking at

`CroppedSelectionPreview.swift:332` renders `record?.displayedTranslation ?? translation`, so the
cloud translation replaces the on-device one on screen as soon as it arrives. The card therefore
stores **whatever that expression evaluates to at the moment add is tapped** — on-device if the
reader added straight after translating, cloud if they asked for an explanation and waited.

That is the point rather than an accident: the stored translation is the one the reader read and
judged correct. Nothing upgrades it afterwards. Editing arrives in stage 2.

### Endpoints

```
POST /cards   -> 201 with the new card, or 200 with the existing one
GET  /cards   -> list[CardResponse], newest first, excluding archived
POST /cards/{id}/lookups -> 204
```

`POST /cards` is **idempotent on (normalized_key, target_language)**: a duplicate returns the
existing card with 200 rather than 409. The offline queue replays blindly, and a replay must not
be an error.

`POST /cards/{id}/lookups` increments `lookup_count` and sets `last_looked_up_at`. It does not
touch `due_on` — rescheduling on a hit belongs to stage 3, where scheduling exists.

*Accepted imprecision*: a lookup report whose response is lost after the server commits will be
retried and counted twice. Deduplicating it needs a per-event table; for a counter that only
feeds a weighting, the cost is not worth paying. Recorded here so it is not later mistaken for a
bug.

### The client seam

`Networking/LearningCard.swift` (`Decodable` only, like every other display model),
`StudyRepository` protocol + `APIStudyRepository`, injected through an `EnvironmentKey` — the
shape of `ComprehensionRepository.swift` / `APIComprehensionRepository.swift`.

### The deck snapshot

`DeckSnapshotStore`: protocol, `FileDeckSnapshotStore`, `InMemoryDeckSnapshotStore`. It stores the
**raw `GET /cards` response bytes**, for the reason `CatalogSnapshotStore` gives: the models are
`Decodable`-only and should stay that way.

Refreshed after a successful list or add, and on app foreground. Matching decodes the snapshot and
compares normalised keys. A missing or stale snapshot means "not collected" — the marker is a
courtesy, never a correctness requirement.

### The offline queue

`PendingCardStore` (protocol / file / in-memory) holding `PendingCard` values, plus a
`PendingCardFlusher` actor that mirrors `PendingProgressFlusher` exactly: oldest first, remove
only once the server has taken it, **drop on 4xx** so one bad entry cannot wedge the queue, stop
on anything else.

Flush opportunistically whenever any card call succeeds — the same trick
`OfflineFallbackComicRepository` uses, where a success is the proof that the network is back.

Enqueueing deduplicates on the normalised key, so tapping add twice offline queues one card. A
queued card counts as collected for the local marker.

### The button

Lives beside the translation result, in the same region as the existing explain prompt.

- Hidden until a translation has loaded; disabled while `editedText` trims to empty.
- **Idle** — "Add to vocabulary". **In flight** — a progress state. **Collected** — a static
  "In your vocabulary". There is no remove: stage 1 ships without management, by decision.
- If the deck snapshot already contains the key when the translation loads, the button starts in
  the collected state and an **already learned** marker appears beside the translation, which
  still shows the meaning in full.
- Offline, tapping enqueues and moves straight to the collected state.

### Comment to update

`CroppedSelectionPreview.swift:66` — `editedText` is no longer "never written anywhere". The
replacement must say what is now true: it is the text a card is created from, and the only text
the reader has confirmed.

## Testing Decisions

Backend (pytest, following the existing `comprehension_store` tests):

- The normalisation vector table above, case for case.
- `POST /cards` twice with the same key returns 200 and creates one row.
- The unique constraint holds against a direct second insert.
- `GET /cards` ordering and archived exclusion.
- `POST /cards/{id}/lookups` increments and stamps; unknown id is 404.

iOS (`vista_comicTests`):

- The **same** normalisation vector table, verbatim.
- Deck snapshot: decode, hit, miss, absent snapshot, malformed bytes.
- Queue: enqueue, dedupe on key, flush order, 4xx drop, non-4xx stop, no double flush.

**No XCUITest is written, built, or run.** UI verification is handed over as this checklist:

1. Compact and larger phone: the button's three states, and that it never overflows beside the
   depth picker and explain button.
2. Select a line, add it, dismiss, select the same line again — the already-learned marker
   appears and the meaning is still shown.
3. Aeroplane mode: add two words, confirm both show as collected, restore the connection, open
   the library, confirm both appear in `GET /cards` exactly once.
4. Add a line with a hard line break in it, then select a version without the break — same card.
5. Empty and failed recognition states still behave as before.

## Out of Scope

- Deleting, editing or archiving a card, and any management screen (stage 2).
- Any meaning for `ladder_stage` / `due_on`, and rescheduling on a lookup hit (stage 3).
- Picking individual words out of an explanation's breakdown, practice sentences, cloze and typed
  questions (stage 4).
- Streak, XP, per-comic mastery, and removing 歷史紀錄 (stage 5).
- Offline review. Only collecting works offline in this stage.
- Merging inflected forms of the same word.

## Further Notes

The lookup marker is deliberately built on a local snapshot rather than an endpoint. It costs one
more store, but it is the only arrangement in which the reward the PRD is built around — being
told you already know this — survives the situation the reader is most often in: a downloaded
chapter and no signal.
