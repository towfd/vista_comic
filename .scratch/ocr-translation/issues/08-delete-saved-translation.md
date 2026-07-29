# 08 — Delete a saved translation from 單字本

**What to build:** each row in `VocabularyView`'s list gets a delete action, backed by a new `DELETE /translations/{id}` backend endpoint and a matching `TranslationRepository.delete(id:)` method. This was explicitly out of scope in the original `ocr-translation` spec ("Editing or deleting a saved translation once saved") — the user now wants it.

**Blocked by:** 06 (needs the real list to delete from)

**Status:** resolved

### Backend
- [x] `translation_store.delete_translation(session, translation_id) -> bool`
- [x] `DELETE /translations/{translation_id}`: 204 / 404 / 503
- [x] Backend tests added to `test_translation.py` (delete removes the row, only the targeted row, unknown id → 404, store-unavailable → 503) — **not run locally**: this sandboxed Mac has a native Postgres bound to `127.0.0.1:5432` ahead of docker-compose's published port (confirmed via `lsof`), so `conftest.py`'s `localhost:5432` test-DB connection never reaches the right database (`role "vista" does not exist`) — pre-existing environment issue, unrelated to this change. Verified instead by rebuilding/restarting the real `api` docker container and exercising the endpoint directly against it: created a throwaway row, `DELETE` → 204, confirmed gone via `GET /translations` (real count unaffected), `DELETE` of an unknown id → 404.

### iOS
- [x] `TranslationRepository.delete(id:) async throws`; `APITranslationRepository` implements it via a new `delete(at:)` request helper (ignored response body, mirrors `APIComicRepository.put`)
- [x] `SavedTranslationRow` gets a second trailing icon button (trash), stacked above/below the jump button; delete action passed in as an `onDelete: () async -> Void` closure, not called directly from the row
- [x] Tapping delete shows a destructive-styled `.alert` confirmation ("Delete this translation? This can't be undone.") before anything happens
- [x] `VocabularyView.delete(_:)` calls `TranslationRepository.delete(id:)` (via the new `deleteSavedTranslation` free function, mirroring `saveSelection`'s testable-free-function shape) and removes the entry from `state` in place on success
- [x] Delete failure shows a generic, non-silent alert; entry stays in the list
- [x] Unit tests: `VocabularyDeleteFlowTests.swift` (new), reusing `StubTranslationRepository` from `SelectionSaveFlowTests` — 2/2 pass

## Comments

Requested by the user (2026-07-30) while testing `ocr-translation` PR31, alongside `ocr-recognition` ticket 06 (OCR line-join fix) in the same request.

**Manual verification**: rebuilt/reinstalled on booted iOS 18.1 simulators (iPhone SE, iPhone 16 Pro Max) — both jump and delete icons render correctly at both sizes. Full delete round trip verified against the real backend: created a throwaway "delete-verify" entry via curl, temporarily wired `VocabularyView` to run the exact same `delete(_:)` code path a confirmed alert tap would run (this sandboxed environment has no tap-automation tool, same limitation noted in `tab-bar-navigation` ticket 01), confirmed the entry both disappeared from the in-app list *and* was gone from the backend (`GET /translations` count back to 2, the user's real entries untouched) — then reverted the temporary wiring, confirmed clean via `git diff`.
