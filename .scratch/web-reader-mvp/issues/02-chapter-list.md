# 02 — Pick a comic, see its chapters

**What to build:** Clicking a comic in the library opens its chapter list — every chapter in reading order with its number, title and page count — and the browser's back button returns to the library. Chapters are not yet openable.

The screen is driven by `GET /comics/{comicId}` through the client, store and proxy ticket 01 built; nothing new is needed below the component layer except a store action for one comic's detail.

**Routing is history-mode**, at `/comic/:comicId`. Under the Vite dev server a refresh or a typed URL on that path serves the app, so no catch-all is needed — that concern belonged to the deferred public-hosting design, where FastAPI serves the files.

**The `readState` badge is the one deliberate inclusion next to a cut.** The response already carries each chapter's `readState`, so the list shows read / reading / unread — chapters read on the phone become visible here. It displays only and never writes progress. If the developer would rather not have it, it is removed without touching anything else.

A comic id that the backend does not know (a stale bookmark, a rescanned library) is a 404 from the API and must render as "找不到這部漫畫" with a way back to the library, not as a generic failure.

**Blocked by:** 01

**Status:** done 2026-10-06 — unit-verified, checked against the live backend, and reviewed in the browser by the developer on branch `feature/web-reader-mvp`.

- [x] Clicking a comic in the library navigates to `/comic/:comicId`
- [x] The chapter list shows every chapter in reading order with number, title and page count
- [x] Each chapter shows its `readState` as a badge, display only — **reading and read only; see deviation below**
- [x] Browser back returns to the library; refreshing on `/comic/:comicId` reloads the same chapter list
- [x] Loading, failure-with-retry and empty states are handled, reusing ticket 01's error shaping
- [x] An unknown comic id renders a not-found message with a link back to the library
- [x] Nothing writes reading progress
- [x] No server, iOS, `docker-compose.yml` or `cloudflared/` file is modified

## Browser checklist for the developer

- [ ] Click a comic: its chapters appear, in the right order
- [ ] A chapter you finished on the phone shows as read; one you are midway through shows as reading
- [ ] Back returns to the library; refresh on the chapter list keeps you there
- [ ] Change the comic id in the address bar to nonsense: a not-found message with a way back

## Deviations from the ticket, decided against the real data

- **`unread` gets no badge.** The ticket asked for all three. The live library made that noise: 141 of Frieren's 146 chapters are unread, and all but 5 of Conan's 1162. A badge on nearly every row says nothing; the absence of one now means unread, and the two states worth seeing — reading and read — stand out.
- **Chapters are labelled `第 N 話` from `number`.** Every title in the library is the English `Chapter N`, which repeats the number. The title is still shown beside it whenever it is anything other than `Chapter <number>`, so a comic with real chapter names loses nothing.

## What was built

- `api/types.ts` — `ReadState`, `ChapterSummary`, `ComicDetail`. `readState` is typed to allow unknown strings, which render no badge.
- `api/client.ts` — `fetchComic`, which rewrites the comic cover **and every chapter's own `coverUrl`**. The ticket did not mention chapter covers; they are absolute too, and nothing renders them yet, which is exactly when an un-rewritten URL gets missed.
- `stores/comics.ts` — one entry per comic id, so going back to a chapter list already seen does not round-trip through Cloudflare again.
- `views/ComicView.vue` at `/comic/:comicId`; `LibraryView` now links each comic to it.
- `components/ErrorState.vue` — hides retry for `notFound` (retrying a 404 asks the same question for the same answer), takes a `notFoundTitle`, and an `actions` slot so the caller supplies "回到書庫" instead of the component hardcoding a route.

## Verification done

- `vue-tsc` clean; 16/16 unit tests (4 new: both cover rewrites, order preserved, encoded id, 404 → `notFound`).
- Live, through the proxy: `/comics/<frieren>` → 146 chapters; `/comics/nonsense` → 404 `Comic not found`.
- `GET /comic/<id>` with `Accept: text/html` → 200 HTML, so a refresh on the chapter list serves the app.
- Incidentally: Cloudflare refuses requests carrying Python's default `User-Agent` (403) while curl and browsers pass. Irrelevant to the reader, noted in case a script ever hits the API.
