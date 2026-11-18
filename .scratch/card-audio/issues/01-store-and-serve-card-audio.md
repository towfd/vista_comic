Status: done (2026-11-18)
Blocked by: —

# 01 — Store and serve a card's audio

**What to build:** The backend half. The `card_audio` table exists in the schema, a card's recording can be fetched by its id, and every card response says whether the card has a current recording. After this ticket is deployed, the owner creates the `card_tts` role (spec, "The writer's role") and the Text-To-Speech writer can start filling the table.

**Files (boundary):**
- `backend/alembic/versions/7e893400bb25_card_audio.py`: create `card_audio` (spec, "The table"), revises `b6e2f0c4a913`; downgrade drops it
- `backend/app/db.py`: `CardAudio` model matching the migration (the `audio` column deferred, so loading a row never drags its bytes along); `LearningCard.has_audio`, a read-only SQL expression: a `card_audio` row exists for the card **and** its `source_text` equals the card's
- `backend/app/models.py`: `hasAudio: bool` on `LearningCardResponse`
- `backend/app/main.py`: `_to_card_response` fills `hasAudio`; new `GET /cards/{card_id}/audio`
- `backend/tests/conftest.py`: `card_audio` joins the `TRUNCATE` statements that name `learning_card`
- `backend/tests/test_card_audio.py` (new)

**Acceptance criteria:**
- [x] Migration upgrades and downgrades cleanly; `tests/test_migrations.py` finds no drift between the models and the migrations.
- [x] `GET /cards/{id}/audio` with a current row: `200`, body is the bytes, `Content-Type` is the row's `mime_type`, `Cache-Control: no-cache`, an `ETag` built from `card_id` and `created_at`.
- [x] The same request with a matching `If-None-Match` (also as `W/"..."`): `304`, no body, same headers.
- [x] A regenerated row (new `created_at`) gets a new `ETag`.
- [x] `404` when the card does not exist, has no row, or its row's `source_text` differs from the card's.
- [x] Every `/cards` response carries `hasAudio`: `true` for a current row, `false` with no row or a stale one. `PUT /cards/{id}/source-text` answers `hasAudio: false` once the text changes; `PATCH`, reset and `POST` (200 for an existing card) answer it correctly too.
- [x] Deleting a card deletes its `card_audio` row (the foreign key cascades).
- [x] Full backend suite passes.

**Owner check after deploy:** Create the `card_tts` role in `psql` (SQL in the spec). Nothing changes on screen yet: no card has audio until the writer runs, and the play button is ticket 02.

## Comments

2026-11-18: implemented. Backend suite: 450 pass (28 new in `tests/test_card_audio.py`). `tests/test_migrations.py` finds no drift.

Decisions made while implementing:
- `db.card_audio_is_current` is the one definition of "current" (row exists and its `source_text` equals the card's). Both `LearningCard.has_audio` (a `column_property` holding an `EXISTS`) and the audio route use it, so the flag and the 404 cannot disagree.
- `has_audio` is an SQL expression, so SQLAlchemy expires it whenever the card is written and reloads it on the next access. `reset_card` now builds its response inside the session for that reason.
- The ETag hashes `card_id` and `created_at` in UTC, so the tag does not change with the connection's time zone.
- An archived card's recording is still served if current: the writer skips archived cards, and the web never shows them.

2026-11-18: merged as #162 (`a63085f`) and deployed: `api` and `web` rebuilt on the home server. The api ran `b6e2f0c4a913 -> 7e893400bb25` on start; `card_audio` exists and is empty. Through `localhost:8080`: all 324 cards answer `hasAudio: false`, and `/cards/186/audio` and `/cards/999999/audio` answer 404. Next: the owner creates `card_tts`; then tell the `text-to-speech` session, and start ticket 02.

2026-11-18: `card_tts` created at the owner's request (`CREATE ROLE card_tts LOGIN` and the two `GRANT`s from the spec, run here); the owner set its password with `\password` themselves, so it was never seen in this session. Checked: login, not superuser, `SELECT` on `learning_card(id, source_text, archived_at)` only, `SELECT, INSERT, UPDATE` on `card_audio` (no `DELETE`), no `CREATE` on `public`. Connections from outside the container use scram-sha-256. The `text-to-speech` session was told it can start.

