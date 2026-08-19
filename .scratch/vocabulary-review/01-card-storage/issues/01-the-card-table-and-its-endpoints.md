# 01 — The card table and its endpoints

**What to build:** The backend half of collecting. A table that holds one line the reader has confirmed, and the three endpoints the app will use. Nothing is user-visible when this ticket lands.

It goes first because every other ticket in this stage — and every stage after it — reads or writes this table, and because it is the only piece that can be fully verified without a device.

**Card identity is a normalised key plus target language, and it is global.** The comic a line came from is deliberately not part of the identity: the same word met in another work is the same word, and splitting it would fragment the lookup count that stage 3 reads as a forgetting signal. The normalisation rules and their vector table are in `spec.md` — implement them exactly, because ticket 03 implements the same table again in Swift and the two must agree.

**`POST /cards` is idempotent rather than conflicting.** A duplicate returns 200 with the existing card, not 409. Ticket 04's offline queue replays blindly, and a replay must not be an error.

`ladder_stage` and `due_on` are written here and given meaning in stage 3. Nothing in this stage reads them.

**Blocked by:** nothing.

**Status:** done — full backend suite green (207 passed), and confirmed running against the real deployment on 2026-08-19: the migration created `learning_card` at API startup with no manual step, and `POST /cards` / `GET /cards` answered end to end.

- [x] An Alembic revision on top of `4085885413a9` creates `learning_card`, and downgrades cleanly
- [x] Normalisation matches `spec.md`'s vector table case for case, including `食べた` and `食べる` staying distinct
- [x] `POST /cards` creates a card and returns 201
- [x] `POST /cards` with an existing `(normalized_key, target_language)` returns 200 with the existing card and creates no second row
- [x] A unique constraint on `(normalized_key, target_language)` holds against a direct second insert
- [x] `source_text` over 200 characters is rejected
- [x] Text that normalises to empty is rejected
- [x] `GET /cards` returns newest first and excludes archived rows
- [x] `POST /cards/{id}/lookups` increments `lookup_count`, stamps `last_looked_up_at`, leaves `due_on` untouched, and 404s on an unknown id
- [x] The store is a module of plain session-taking functions, matching `comprehension_store`
- [x] Response models are camelCase, matching the existing API contract

## What was built

- `app/normalization.py` — `normalized_key`, in its own module because it is the one rule this feature implements **twice** (again in Swift, ticket 03). NFKC, then remove every whitespace character, then lowercase. The docstring carries the reason inflected forms stay separate, so the next reader meets the argument rather than the limitation.
- `app/db.LearningCard` — the table, with `UniqueConstraint("normalized_key", "target_language")` as the card's identity.
- `alembic/versions/9c41a7be03d5_learning_card.py` — hand-written on top of `4085885413a9`, then checked by the drift guard rather than trusted.
- `app/learning_card_store.py` — `create_or_get`, `list_active`, `get`, `record_lookup`. Plain session-taking functions, matching `comprehension_store`.
- `app/models.py` — `LearningCardCreate` (with the 200-character cap as a field constraint) and `LearningCardResponse`.
- `app/main.py` — `POST /cards`, `GET /cards`, `POST /cards/{id}/lookups`.

**`_comprehension_session` was generalised into `_store_session(detail, log)`.** `/cards` is the third resource to want the identical open/rollback/close-or-503 dance, and the existing helper's own docstring said it was extracted the first time the shape had to be repeated. `_comprehension_session` is now a two-line alias, so no comprehension route changed.

**Three decisions the spec did not settle, made here and worth review:**

1. **An archived card is revived, not shadowed.** The unique constraint spans archived rows, so without this the reader could press add, be told the word is collected, and never find it in a list that excludes archived cards. `archived_at` is always NULL in this stage, so the path only matters from stage 2 — which is exactly when getting it wrong would be confusing.
2. **`comprehension_record_id` is a real foreign key with `ON DELETE SET NULL`**, not a bare integer. Deleting a history row must never delete something the reader deliberately kept. It is always NULL until stage 4.
3. **`created_at` uses the database clock** (`func.now()`), matching `progress_store.upsert` and `comprehension_store.insert_record`. `due_on` stays an application-side UTC date, since it is a scheduling date rather than an event timestamp.

## Verification

`207 passed in 7.43s` — the whole backend suite, not only the new file. 31 of those are new or newly touched:

- The eight-row normalisation vector table, parameterised, plus an explicit test that `食べた` and `食べる` stay distinct — so a future "fix" that merges them fails a test whose name says it is deliberate.
- Idempotency: adding twice returns 200 with the same id and leaves one row; a line with a hard line break matches the same line without one; the same word from another comic is the same card; the same word in another language is not.
- The unique constraint asserted **directly**, with a raw second insert expecting `IntegrityError`, rather than inferred from the store's behaviour — the store's pre-check is a convenience, and the constraint is what makes the race safe.
- Refusals: over the cap, at the cap, whitespace-only, empty.
- Listing: newest first, archived excluded.
- Lookups: counted and stamped, `due_on` and `ladder_stage` untouched, 404 for a card that is gone.
- The migration drift guard (`test_the_migrated_schema_matches_the_models`) passes, which is what makes the hand-written revision trustworthy, and the downgrade test now asserts `learning_card` is dropped too.

**One regression was introduced and fixed.** The new foreign key made the existing `comprehension_db` fixture fail: Postgres refuses to `TRUNCATE` a table another table references. Both tables are now named in one `TRUNCATE` statement rather than using `CASCADE`, which would silently reach whatever gets added later. This is the kind of breakage that only shows up in a full-suite run, which is why the whole suite was run rather than the new file alone.

**Not verified here:** nothing is user-visible yet, so there is no device pass to hand over. That begins with ticket 02.
