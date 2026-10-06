# 01 — `continueChapterId` on `GET /comics/{comicId}`

**What to build:** `ComicDetail` gains `continueChapterId: str`, so the web chapter list can offer Continue without fetching the whole library. `get_comic` already queries this comic's progress `rows`; it passes them with `comic.chapters` to the existing `progress_store.continue_chapter_id` — the same function `GET /comics` uses, so the two endpoints can never disagree. See the spec's "Backend" section.

With the progress store down, `rows` is `{}` and the value degrades to the first chapter, exactly as on the list endpoint. iOS is unaffected (`Codable` ignores unknown keys).

**Deploying is the developer's step.** Nothing here touches `docker-compose.yml`, `cloudflared/`, or the iOS app.

**Blocked by:** none

**Status:** ready

- [ ] `ComicDetail` in `backend/app/models.py` has `continueChapterId: str`
- [ ] `get_comic` fills it with `progress_store.continue_chapter_id(comic.chapters, rows)` — no extra query
- [ ] pytest: the detail's `continueChapterId` equals the list endpoint's for the same comic — with no rows (first chapter), with a `reading` chapter, and with every chapter `read` (first chapter)
- [ ] pytest: with the progress store unavailable, the detail still returns 200 with the first chapter
- [ ] `docs/api-contract.md` documents the field on `GET /comics/{comicId}`
- [ ] Full backend suite passes
