# 06 — Say whether it is a word or a sentence

**What to build:** Two save buttons instead of one — **加入單字** and **加入句子**. The reader says which it is at the moment they collect it.

**This is the same move as manual add, applied to a second problem.** Whether a framed line is a word or a sentence is something the reader knows instantly and a machine has to infer from tokenisation and syntax — badly, for Japanese especially. One tap replaces all of that, costs nothing, and is authoritative.

**It also closes a gap left open since the PRD.** Stage 4's cloze question needs to know which word in a sentence to blank; for a card that *is* a sentence, that had to wait for the structured breakdown to come back and tell us. With `kind` declared at collection time, half of that question is answered before it is ever asked.

**The two kinds have to lead different lives, or the buttons are two names for one action.** They do:

| | Word card | Sentence card |
|---|---|---|
| Front | a word or set phrase | the whole line |
| Stage 3 questions | matching, typed answer | cloze |
| Stage 4 generation | a sentence is generated **for** it, and it is what gets blanked | none — it already is real language, which is better than anything generated |

Sentence cards therefore also cost less: they need no LLM call to become usable.

**`kind` is not part of card identity.** Identity stays `(normalized_key, target_language)`, for the same reason it ignores which comic a word came from: splitting it fragments the `lookup_count` that stages 3 and 4 read, and it would put two visually identical rows in the library with the already-learned marker answering differently for each. Collecting the same line again under the other button returns the existing card **unchanged** — the system never silently rewrites something the reader already approved. Changing it is done in 單字庫 (`../../02-card-library/`).

**`kind` is nullable, and existing cards keep NULL.** The deck predates this column, and backfilling it means guessing a classification — exactly what this ticket exists to abolish. Unclassified cards are treated as word cards by stage 3 (matching and typed answers work on any text; only cloze needs a real sentence) and can be set in 單字庫.

**Blocked by:** 02 — Add a word from the selection sheet.

**Status:** implemented on branch `feat/deck-lookup-marker`, 2026-08-19 — backend `212 passed`, iOS `TEST BUILD SUCCEEDED` and `xcodebuild test` exit 0 with zero test-case failures. **Device-verified by the repo owner, 2026-08-20**: both buttons lay out without truncation on a compact phone, a collected card records the kind chosen, the kind survives the offline queue, and **every card predating the column still has NULL** rather than a guessed value.

- [x] An Alembic revision adds a nullable `kind` to `learning_card`, and downgrades cleanly
- [x] `POST /cards` accepts `kind` of `word` or `sentence`; an unrecognised value is rejected rather than stored
- [x] `kind` is absent-able, and a card collected without one has NULL
- [x] Collecting an existing line under the other button returns the existing card with its `kind` **unchanged**, still 200
- [x] `kind` is not part of the unique constraint
- [x] `GET /cards` returns `kind`, and the deck snapshot carries it
- [x] The selection sheet offers both buttons, and both are disabled when the corrected text trims to empty
- [x] Both buttons fit a compact phone alongside the depth picker and the explain button, stacking rather than truncating
- [x] The collected state names which kind was chosen, so a mis-tap is visible immediately rather than weeks later
- [x] Offline, both buttons queue, and the queued entry carries its `kind`
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `alembic/versions/c73f5b1de204_learning_card_kind.py` and `db.LearningCard.kind` — nullable.
- `learning_card_store.create_or_get(kind:)`, and `CARD_KINDS` naming the two accepted values.
- `LearningCardCreate.kind` as `Optional[Literal["word", "sentence"]]`, so an unrecognised value is refused by the model rather than reaching stage 3 as a card no question type knows how to ask about.
- `CardKind` in Swift, `LearningCard.kind`, `PendingCard.kind`, and the kind threaded through `StudyRepository.collect` and the offline decorator.
- Two buttons in the selection sheet, side by side via `ViewThatFits`.

**Four decisions worth review:**

1. **Two buttons, not one button plus a type picker.** The choice *is* the action — the reader knows which it is at the moment they decide to keep it, and setting a type first would put a decision in front of the thing they came to do.
2. **The confirmation names the kind** — "Added as a word" / "Added as a sentence". Two adjacent buttons will be mis-tapped, and without this the mistake surfaces weeks later when stage 3 asks the wrong sort of question. A card with no kind falls back to the vague wording rather than inventing one.
3. **`CardKind` is `Codable`**, unlike the display models around it, because the offline queue persists it. A relaunch must not lose the answer along with the word.
4. **`isQueued` became `queuedEntry(for:...)`**, returning the entry rather than a Bool, so a queued line can name its kind too. Same rule everywhere: if the screen says something was kept, it says *how*.

`kind` is deliberately absent from the payload rather than sent as null when unanswered.

## Verification

**Backend: `212 passed`** — the whole suite, including the migration drift guard, which is what makes the hand-written revision trustworthy. Five tests are new: both kinds recorded, a collect with no kind leaving NULL, an unrecognised kind refused with 422 and no row created, re-collecting under the other button returning the existing card with its **kind unchanged**, and kind not being part of identity.

**iOS: `TEST BUILD SUCCEEDED`, then `xcodebuild test` exit 0 with zero test-case failures**, 380 passing cases. Six are new: the chosen kind reaching the backend for both kinds (parameterised), decoding both kinds, an absent kind decoding as unanswered, **an unrecognised kind decoding as unanswered rather than failing the whole list** (following `ComprehensionStatus`'s precedent), the kind surviving the offline queue for both kinds, and **a queue file written before this column existed still decoding** — the field is optional precisely so an older queue does not take the reader's offline words down with it.

No XCUITest was written, built, or run.

## Device checklist for the repo owner

1. Translate a selection. **Both buttons appear side by side**, under the translation and above the 深入解釋 offer.
2. **On the narrow phone**, confirm they stack into two rows rather than truncating, and that nothing collides with the depth picker or the explain button.
3. Tap **Add as word**. The confirmation says **"Added as a word"** — not a generic message.
4. On another selection tap **Add as sentence**, and confirm it says so.
5. **Tap the wrong one on purpose**, then re-frame the same line and tap the other. It stays as first saved, and the confirmation still names the original kind. That is intended: 單字庫 (spec-02) is where a mis-tap gets corrected.
6. Clear the text: **both** buttons disable together.
7. **Airplane mode**: collect one of each, force-quit, relaunch, reconnect. Both arrive with the right kind — check `SELECT source_text, kind FROM learning_card`.
8. Your two existing cards still show as collected and their `kind` is **NULL**, not guessed.

## A finding from the device pass, not a defect

Three cards in the deck are the same Vietnamese sentence, kept apart by OCR reading the
diacritics differently each time (`CẤM`/`CÂM`, `THÂN THÊ`/`THÂN THẾ`).

**The system behaved correctly** — the keys genuinely differ, and no duplicate key exists. And
normalisation must **not** fold diacritics away: in Vietnamese they distinguish words outright
(`cấm` forbid, `câm` mute), so stripping them would merge cards that are not the same word at
all, which is worse than the duplicates.

So this is OCR accuracy, not deduplication. The correction already exists — the reader edits the
recognised text before saving — and spec-02's delete clears whatever slipped through. Recorded
so the next person meeting three near-identical cards does not "fix" the normalisation.
