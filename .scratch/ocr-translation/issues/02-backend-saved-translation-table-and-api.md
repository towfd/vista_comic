# 02 — Backend: `saved_translation` table + save/list API

**What to build:** a new Postgres table storing saved translation pairs (original text, translated text, target language, source comic/chapter/page reference, timestamp), plus two endpoints — one to save a new entry, one to list all saved entries — following the existing `progress` table's precedent (`CREATE TABLE IF NOT EXISTS`, no migration tooling). Purely backend; no iOS changes.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] New table created on backend startup if it doesn't exist, matching the `progress` table's setup pattern
- [ ] `POST` endpoint saves a new translation entry (original text, translated text, target language, source reference) and returns it
- [ ] `GET` endpoint lists all saved entries
- [ ] Backend tests cover both endpoints, following `backend/tests/`'s existing conventions for the `progress` endpoint
- [ ] Verified with `curl` against the running backend: save an entry, list it back, confirm the fields round-trip correctly
