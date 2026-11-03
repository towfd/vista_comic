Status: implemented — awaiting deploy check by owner (2026-11-04)
Blocked by: —

# 01 — Write a note on the card page

**What to build:** The first path end to end. The backend stores an optional note on a card, and the web card page reads, edits, and clears it. After this ticket, any existing card can be given a note.

**Files (boundary):**
- `backend/app/db.py`: `LearningCard.note` nullable text column
- `backend/alembic/versions/<new>_card_note.py`: add the column, downgrade drops it
- `backend/app/models.py`: `note` on `LearningCardResponse`, `LearningCardCreate` (optional), and `LearningCardUpdate` (`max_length` 1000 after trimming)
- `backend/app/learning_card_store.py`: `create_or_get` sets the note only on create; `update` sets the note when asked (`set_note`, as `set_kind`)
- `backend/app/main.py`: `create_card` passes the note; `update_card` reads `note` from `model_fields_set` and accepts a note-only body; `_to_card_response` returns it; the "Provide translation, kind, or both" message names `note`
- `backend/tests/test_learning_cards.py`
- `web/src/api/types.ts`: `note: string | null` on `LearningCard`, `note?` on the create and update bodies
- `web/src/views/DeckCardView.vue`: a 註解 textarea under the translation, saved with the existing button
- Web tests where the deck store or client code changes

**Acceptance criteria:**
- [x] Migration upgrades and downgrades cleanly. Existing cards have `note: null`.
- [x] `POST /cards` with a note stores it, trimmed. Blank stores `null`. A `200` for an already-collected line leaves the existing note unchanged.
- [x] `PATCH` with only `note` updates it. `null` or blank clears it. A `PATCH` without `note` (iOS's body: `translation` + `kind`) leaves it unchanged.
- [x] A note over 1000 characters after trimming is refused with `422`. Exactly 1000 is accepted.
- [x] Every `/cards` response carries `note`.
- [ ] Card page: shows the note and saves an edit. Clearing the field and saving clears it. Line breaks survive a round trip. Saving only the note does not touch the translation.
- [x] Full backend test suite passes. `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** On a card page, write a two-line note, save, reload: both lines are still there. Clear it, save, reload: it is gone. Edit the translation on the phone: the note is still there on the web.

## Comments

2026-11-04: implemented. Backend: 397 tests pass (7 new: no note by default, trimmed with line breaks kept, blank is none, re-collecting keeps the note, note-only PATCH writes/changes/clears, a PATCH without `note` leaves it, cap at 1000 after trimming). Migration `b6e2f0c4a913` upgraded, downgraded and re-upgraded on a throwaway database. Web: typecheck, build and 417 tests pass (2 new in `client.test.ts`: a note sent alone, a response without `note` reads as none). The card page itself is not unit-tested.

The note's cap lives in `models.py` (`MAX_NOTE_LENGTH`) rather than `learning_card_store.py`: `models` imports no app module, and reaching the store would pull in the database config. The card page saves the note with its own 儲存 button, as each field there does.
