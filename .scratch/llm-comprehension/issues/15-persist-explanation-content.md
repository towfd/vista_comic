# 15 — Persist explanation content alongside translations

**What to build:** extend `saved_translation` with three new nullable columns (`grammar_notes`, `context_notes`, `tone_register`), extend `POST`/`GET /translations` to accept/return them, and wire the iOS "Save" action (already calling `TranslationRepository`, unchanged protocol shape) to actually pass these fields through when they exist. A save made from a fallback result (ticket 14's gray/orange banner states) still succeeds, with these three fields simply absent/NULL — no separate provenance column, per the spec. Demoable by translating, saving, and confirming the full record (including explanation) round-trips through the backend.

**Blocked by:** 14

**Status:** resolved

- [x] `saved_translation` gains `grammar_notes`, `context_notes`, `tone_register` — all nullable — via `CREATE TABLE IF NOT EXISTS`-style addition, no migration tooling, matching this table's existing columns
- [x] `POST /translations` accepts the three new optional fields and persists them (or persists them as NULL when absent)
- [x] `GET /translations` returns the three fields when present
- [x] Saving a full cloud-explained result persists all three fields correctly
- [x] Saving a fallback-only result (translation-only, from ticket 14's declined/error path) succeeds and persists NULL for all three fields — no error, no silently-dropped save
- [x] `TranslationRepository`'s protocol shape itself is unchanged (only its payload grew) — no new protocol introduced
- [x] `APITranslationRepositoryTests` is extended (not replaced) to cover the three new fields round-tripping through save and list, using the existing stub pattern
- [x] Backend tests for `/translations` are extended to cover the three new columns, including the NULL case

## Comments

Implemented on `feat/llm-comprehension-foundation`, alongside ticket 16 in the same pass.

Backend: `db.py`'s `SavedTranslation` model gains three nullable `String` columns; `translation_store.insert_translation` and `models.py`'s `SavedTranslationCreate`/`SavedTranslationResponse` grow to match; `main.py`'s `save_translation`/`_to_translation_response` thread them through. `test_translation.py` extended with store- and endpoint-level round-trip tests for both the populated and NULL cases.

**Existing-table caveat (worth flagging explicitly):** `create_all`'s `CREATE TABLE IF NOT EXISTS` only creates a table that doesn't exist yet — it never retrofits columns onto one that already does, and both the dev (`vista`) and test (`vista_test`) Postgres databases already had `saved_translation` from earlier tickets. To make the new columns actually exist, I ran additive `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (nullable, no data loss, easily reversible) against both databases in the running local Docker containers, then rebuilt and restarted the `api` container so it picked up the code change. Verified live: `POST /translations` with all three explanation fields round-trips correctly through the real running dev backend.

iOS: `TranslationRepository.save(...)` grows three new `String?` parameters (protocol shape unchanged, payload grown, per the AC); `APITranslationRepository` sends them only when non-nil (omitted, not JSON `null`); `SavedTranslation` gains the three fields plus a `hasExplanation` computed property (used by ticket 16). `saveSelection`/`CroppedSelectionPreview.save(outcome:)` in `ComicView.swift` extract the three fields from a `.comprehended` `SelectionTranslateOutcome`, leaving them `nil` for a fallback outcome. `StubTranslationRepository`/`PreviewTranslationRepository` conformances updated to match; `SelectionSaveFlowTests` gains two new tests (explanation fields passed through when provided, omitted when not) and stays otherwise unmodified; `APITranslationRepositoryTests` extended with save/list round-trip tests for the new fields, with the five pre-existing direct `.save(...)` calls mechanically updated to pass `nil` for the three new required params.

Verified: `xcodebuild build` succeeds; `xcodebuild test -only-testing:vista_comicTests` all pass, no regressions. `.venv/bin/pytest` (backend, full suite) all pass. Build-verified on `iPhone SE (3rd generation)` and `iPhone 16 Pro Max`.

Code review (`/code-review`, Standards + Spec axes, run jointly with ticket 16): no hard violations on either axis. Standards axis flagged two judgement calls, neither actioned: (1) the `save(...)` parameter growth reads as a proportionate extension of the codebase's existing flat-primitives convention, not a new smell; (2) a tiny `jsonStringOrNull` JSON-encoding helper is duplicated between the preview factory and the new test file's helper — low severity, left as-is since sharing it would cross an app/test target boundary for marginal benefit.
