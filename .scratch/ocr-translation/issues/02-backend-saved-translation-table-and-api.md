# 02 — Backend: `saved_translation` table + save/list API

**What to build:** a new Postgres table storing saved translation pairs (original text, translated text, target language, source comic/chapter/page reference, timestamp), plus two endpoints — one to save a new entry, one to list all saved entries — following the existing `progress` table's precedent (`CREATE TABLE IF NOT EXISTS`, no migration tooling). Purely backend; no iOS changes.

**Blocked by:** None — can start immediately

**Status:** resolved (commit `bcb01a8` on `feat/ocr-translation-foundation`)

- [x] New table created on backend startup if it doesn't exist, matching the `progress` table's setup pattern
- [x] `POST` endpoint saves a new translation entry (original text, translated text, target language, source reference) and returns it
- [x] `GET` endpoint lists all saved entries
- [x] Backend tests cover both endpoints — **verified by running**: `backend/tests/test_translation.py`, 12 tests, plus the full backend suite (92/92) confirmed no regressions
- [x] Round-trip correctness confirmed via `TestClient(main.app)` hitting real route handlers against a real (throwaway `vista_test`) Postgres database — functionally equivalent to a curl round-trip. **Live curl against the running docker-compose stack was deliberately skipped**: that stack is the coordinator's real backend, and Docker containers aren't scoped to a git worktree, so rebuilding/restarting it from a worktree risked interrupting the live service for no verification benefit beyond what the tests already prove.

## Comments

Chose 503-on-unavailable for both endpoints (not graceful degradation to `[]`/silent failure, unlike `progress_store`'s read-side `safe_*` wrappers) — reasoned and documented in `translation_store.py`'s module docstring: unlike the catalog, which is independently scan-derived and must survive a DB outage, the `saved_translation` table is the only place this data lives, so degrading `GET /translations` to an empty list would misrepresent "the store is down" as "nothing has been saved."

`comicId`/`chapterId`/`pageNumber` are stored without catalog-existence validation (no 404 for stale IDs) — deliberate, mirrors `Progress`'s own tolerance of orphaned-but-harmless rows after a library reorg.
