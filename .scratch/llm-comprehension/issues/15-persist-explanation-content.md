# 15 — Persist explanation content alongside translations

**What to build:** extend `saved_translation` with three new nullable columns (`grammar_notes`, `context_notes`, `tone_register`), extend `POST`/`GET /translations` to accept/return them, and wire the iOS "Save" action (already calling `TranslationRepository`, unchanged protocol shape) to actually pass these fields through when they exist. A save made from a fallback result (ticket 14's gray/orange banner states) still succeeds, with these three fields simply absent/NULL — no separate provenance column, per the spec. Demoable by translating, saving, and confirming the full record (including explanation) round-trips through the backend.

**Blocked by:** 14

**Status:** ready-for-agent

- [ ] `saved_translation` gains `grammar_notes`, `context_notes`, `tone_register` — all nullable — via `CREATE TABLE IF NOT EXISTS`-style addition, no migration tooling, matching this table's existing columns
- [ ] `POST /translations` accepts the three new optional fields and persists them (or persists them as NULL when absent)
- [ ] `GET /translations` returns the three fields when present
- [ ] Saving a full cloud-explained result persists all three fields correctly
- [ ] Saving a fallback-only result (translation-only, from ticket 14's declined/error path) succeeds and persists NULL for all three fields — no error, no silently-dropped save
- [ ] `TranslationRepository`'s protocol shape itself is unchanged (only its payload grew) — no new protocol introduced
- [ ] `APITranslationRepositoryTests` is extended (not replaced) to cover the three new fields round-tripping through save and list, using the existing stub pattern
- [ ] Backend tests for `/translations` are extended to cover the three new columns, including the NULL case
