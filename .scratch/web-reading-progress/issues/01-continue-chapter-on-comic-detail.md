# 01 — `continueChapterId` on `GET /comics/{comicId}`

**What to build:** `ComicDetail` gains `continueChapterId: str`, so the web chapter list can offer Continue without fetching the whole library. `get_comic` already queries this comic's progress `rows`; it passes them with `comic.chapters` to the existing `progress_store.continue_chapter_id` — the same function `GET /comics` uses, so the two endpoints can never disagree. See the spec's "Backend" section.

With the progress store down, `rows` is `{}` and the value degrades to the first chapter, exactly as on the list endpoint. iOS is unaffected (`Codable` ignores unknown keys).

**Deploying is the developer's step.** Nothing here touches `docker-compose.yml`, `cloudflared/`, or the iOS app.

**Blocked by:** none

**Status:** done 2026-10-06 — backend field added and unit-verified (full suite green); deploying to production is still the developer's step.

- [x] `ComicDetail` in `backend/app/models.py` has `continueChapterId: str`
- [x] `get_comic` fills it with `progress_store.continue_chapter_id(comic.chapters, rows)` — no extra query
- [x] pytest: the detail's `continueChapterId` equals the list endpoint's for the same comic — with no rows (first chapter), with a `reading` chapter, and with every chapter `read` (first chapter)
- [x] pytest: with the progress store unavailable, the detail still returns 200 with the first chapter
- [x] `docs/api-contract.md` documents the field on `GET /comics/{comicId}`
- [x] Full backend suite passes

## What was built

- `backend/app/models.py` — `ComicDetail.continueChapterId: str`.
- `backend/app/main.py` — `get_comic` passes `comic.chapters` and the `rows` it already reads (`safe_progress_by_chapter`) to `progress_store.continue_chapter_id`, so there is still one query and one copy of the rule.
- `docs/api-contract.md` — the field is added to the `GET /comics/{comicId}` shape, and the `continueChapterId` note now says the detail endpoint uses the same rule and degrades the same way.

## Verification done

- New tests in `backend/tests/test_progress.py`: the detail's `continueChapterId` equals the list endpoint's for the same comic with no rows (both comics → first chapter), with a `reading` chapter, with a fully read first chapter (→ first unread), and with every chapter `read` (→ first chapter). The existing store-down test (`_SessionLocal = None`) now also checks the detail returns 200 with the first chapter.
- `backend/tests/test_endpoints.py`: the exact-key assertion on the detail shape now includes `continueChapterId`.
- `cd backend && .venv/bin/python -m pytest` → 329 passed (Postgres `vista_test` via `docker compose up -d postgres`).
- Fixture limitation: in `sample_library` the only multi-page Alpha chapter is its first, so the `reading` case also lands on the first chapter. The pure-function tests already cover a `reading` chapter that is not the first.
