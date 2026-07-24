# Backend architecture baseline

Status: **Slices 1–3 implemented** (scan-and-serve catalog + media + iOS client, all merged); **Slice 4 (reading-progress persistence on PostgreSQL, in Docker Compose) is planned and about to start** (decisions recorded 2026-07-23). Values still marked _(proposed)_ are pre-Slice-4 defaults. Milestone status and ownership remain in `PLAN.md`.

## Goal

The smallest backend that makes a **local manga folder on the developer's machine appear in the existing iOS app** (library → chapters → vertical reader). The iOS frontend (M1–M4) is complete and today reads in-app sample data.

## Guiding principle — design the contract, iterate the implementation

The one thing worth designing carefully now is the **API JSON contract + stable IDs**. Everything behind it (in-memory catalog vs. PostgreSQL, cache, containers) is an internal swap the app never sees, so it can be deferred and iterated. The app binds to the contract, not to the storage.

## v1 architecture — one "scan-and-serve" API

A single small HTTP service that, on startup and on a manual re-scan, walks the library folder into an **in-memory catalog** matching the app models, and exposes JSON endpoints plus image bytes.

- The folder stays the **source of truth**; no second copy to keep in sync.
- No schema, migrations, cache invalidation, or container orchestration to design for v1.
- Re-scan on boot is O(folder) and trivially correct/idempotent.

### Components and their triggers

| Component | Status | Trigger / rationale |
| --- | --- | --- |
| PostgreSQL | **Adopted at Slice 4** | Reading progress / last-read position is state the folder cannot reconstruct. A single `progress` table; the catalog stays scan-derived. |
| Docker (Compose) | **Adopted at Slice 4** | Postgres pulls in a container anyway; containerising `api` + `postgres` together buys a reproducible, one-command local stack. Two services: `api`, `postgres`. |
| Redis | **Deferred** | The catalog is already in-memory in the API process, so for one user / one worker a Redis cache is a slower network hop with no job to do. Add it only when there is a concrete job: **multiple uvicorn workers/processes must share one cached catalog** (rescan not repeated per worker), or measured slowness on large libraries / many clients. Then it slots in behind the API's catalog seam as a third Compose service. |
| Auth | **Deferred** | Single developer, own device. Add when more than the developer's device consumes it, or content becomes private (e.g. Cloudflare Access in front of the tunnel). |

### Storage: why not build the database first?

Considered and rejected. "Don't scan the folder on every request" is already solved by the in-memory catalog — the scan runs once at startup / manual re-scan and requests read memory. A database does **not** remove scanning (a scanner must still walk the folder to populate it); it persists the scan result and, more importantly, stores **folder-external state the folder cannot hold** (reading progress). Because the DB sits behind the unchanged API contract, adopting it later is an internal swap the app never sees. Building it first would mean designing a schema against a not-yet-validated folder format plus folder↔DB sync, for no v1 benefit. PostgreSQL (or SQLite) is therefore an explicit later slice, introduced when reading-position persistence is the active task — and even then only the small `progress` store needs it; the catalog stays scan-derived.

## Folder format _(confirmed 2026-07-22)_

Three fixed nesting levels; everything inferred from names; **no required metadata** in v1.

```text
library/                         # the library root (mounted / configured path)
├── Frieren/                     # comic dir      → Comic.title = "Frieren"
│   ├── cover.jpg                # optional explicit cover
│   ├── 01 - The Journey/        # chapter dir     → number = 1, title = "The Journey"
│   │   ├── 001.jpg              # page 1 (natural sort; zero-pad recommended)
│   │   └── 002.png
│   └── 02 - The Mage/
│       ├── 001.jpg
│       └── 002.jpg
└── Spy Family/
    └── 01/                      # no title        → number = 1, title falls back to "Chapter 1"
        ├── 001.webp
        └── 002.webp
```

Rules:

- **Nesting is exactly `library / comic / chapter / page-image`.** A dir under root is a comic; a dir under a comic is a chapter; image files in a chapter are pages.
- **Comic title** = comic directory name.
- **Chapter number + title** = parse the dir name as `^\s*(\d+)\s*(?:[-–_.]\s*(.*))?$` → leading integer is `number`; remainder (if any) is `title`; else `"Chapter <number>"`.
- **Page order** = natural sort of image filenames (`2` before `10`); zero-padding recommended, not required.
- **Accepted extensions** _(proposed)_: `.jpg`, `.jpeg`, `.png`, `.webp` (case-insensitive). Others skipped and reported.
- **Cover rule** _(proposed)_: a `cover.*` at the comic root if present, else the first page (natural sort) of the lowest-numbered chapter. Always yields a cover.
- **Metadata**: none required in v1. Reserve an optional `info.json` (comic, later chapter) for future overrides (display title, author, language, explicit titles); schema not designed yet.
- **Malformed / hidden files** (`.DS_Store`, unsupported types): skipped, counted, reported — never crash.

## API contract _(proposed)_

Smallest surface that drives the three existing screens. Shapes map 1:1 to `Comic` / `Chapter`.

```text
# Library screen  → FavouriteView(comics:)
GET /comics
→ [ { id, title, coverUrl, chapterCount, lastReadAt?, continueChapterId } ]

# Chapter list    → ChapterPageView(comic:)
GET /comics/{comicId}
→ { id, title, coverUrl,
    chapters: [ { id, number, title, pageCount, readState } ] }

# Reader          → ComicView(chapter:)
GET /comics/{comicId}/chapters/{chapterId}
→ { id, number, title,
    pages: [ "<baseUrl>/media/{comicId}/{chapterId}/001.jpg", ... ],
    lastReadPage? }              # 1-based resume position; omitted when no progress (Slice 4)

# Page image bytes (same origin)
GET /media/{comicId}/{chapterId}/{page}
→ image bytes (Content-Type: image/jpeg | image/png | image/webp)

# Save reading progress (Slice 4)
PUT /comics/{comicId}/chapters/{chapterId}/progress
   body: { "lastPage": N }       # 1-based; validated within [1, pageCount]
→ { comicId, chapterId, lastPage, pageCount, updatedAt }   # 404 unknown chapter, 422 out of range
```

Contract notes:

- **Images travel as URL strings the app fetches**, never embedded bytes in JSON. This mirrors today's model: `pageImageNames: [String]` stays an array of strings — only the string's meaning changes from asset name → URL, and the resolver from `Image(name)` → `AsyncImage(url:)`.
- **IDs are server-generated and stable across scans and restarts** — a hash of the item's relative path. **Load-bearing:** reading-progress persistence (Slice 4) keys the `progress` rows on these IDs, so instability would silently orphan saved progress. Path segments in `/media/...` use these opaque IDs, not raw folder names (avoids path-encoding / traversal).
- **Field values by slice**: through Slice 3, `readState` is `unread` for all and `lastReadAt` is null/omitted (no progress store yet). **From Slice 4** both are derived live from the `progress` store: per chapter, no row → `unread`, `lastPage >= pageCount` → `read`, else `reading`; `Comic.lastReadAt` is the max `updatedAt` across that comic's chapters; the reader response adds `lastReadPage`. **`Comic.continueChapterId`** (always present — every comic has ≥1 chapter) is the chapter "Continue" opens: the most-recently-`updatedAt` `reading` chapter, else the first `unread` chapter in reading order, else (all `read`) the first chapter; with the progress store unavailable it degrades to the first chapter. Both `lastReadAt` and `continueChapterId` come from one grouped query over all progress rows (no N+1).
- One origin serves both JSON and media, so the app configures a single base URL.

## Data flow

```text
Host manga folder (source of truth)
        │  startup / manual re-scan: walk dirs, natural sort
        ▼
API scanner ──► in-memory catalog (comics → chapters → ordered page paths)
        │  HTTP JSON (page = image URL strings)
        ▼
iOS repository ──► decodes into the same Comic / Chapter structs
        ▼
AsyncImage(url:) renders covers and pages ──► GET /media/... streams bytes from the folder
```

## iOS integration impact (high level)

Model **shapes barely change**; the source and the image resolver change.

- **One data-source seam:** `HomeView.swift` currently hard-codes `SampleData.comics`; introduce a repository that fetches `/comics`.
- **Three `Image(name)` → `AsyncImage(url:)` sites:** library cover (`ComicListView`), chapter-screen cover (`ChapterPageView`), reader pages (`ComicView.pageView`). The reader's `AsyncImage` phases finally provide the real **loading** state deferred earlier; the existing `failurePlaceholder` slots into `.failure`.
- **New catalog loading / error states** on the library (it only had an empty state before). Main new complexity.
- **`coverImageName` / `pageImageNames` retype to `URL`** (confirmed) — was asset-name `String`, now `URL`. Touches `Models.swift` (coordinator-owned contract) and `SampleData.swift`.
- **Stable IDs:** `Comic.id` / `Chapter.id` must come from the server (path-derived hash), not per-launch random `UUID()`.
- **ATS:** cleartext `http://localhost` / LAN needs an App Transport Security exception in dev; HTTPS tunnels avoid it.

## Connectivity (developer access)

Does not affect the API contract — only which base URL the app points at.

Everything runs **on the dev Mac — nothing is hosted in the cloud**. Only the base URL the app points at changes with the access method (`VISTA_BASE_URL`).

- **Same Wi-Fi:** phone/simulator → the Mac's LAN IP `http://192.168.x.x:PORT` (+ ATS exception). Simulator can use `http://127.0.0.1:PORT`.
- **Stable public URL (recommended when you want a fixed API endpoint): Cloudflare Tunnel** (the `cloudflared` daemon under Cloudflare Zero Trust). It makes an **outbound** connection from the Mac to Cloudflare's edge and maps a hostname to local `localhost:8000` — **no port-forwarding, no static public IP**. A *stable* hostname requires a domain on Cloudflare (free tier works) bound to a **named tunnel** (e.g. `api.yourdomain.com`); the throwaway `trycloudflare.com` URL changes each run and is not stable. **HTTPS terminates at the edge**, so the app needs **no ATS exception**. Keep it a plain tunnel with **no Zero Trust Access policy** for now (an Access login would block the app unless a service token is added — auth stays deferred).
- **Private mesh alternative: Tailscale** (WireGuard) gives the Mac a stable name/IP reachable from the phone within your tailnet — good if you don't want a public URL or a domain.
- In every case uvicorn/the `api` container binds `0.0.0.0`; the base URL is the only moving part.

## Delivery slices (revised — thinner than a DB-first plan)

Each slice ships only when the prior one has an observable acceptance test.

1. **Slice 0 — lock the contract + one real folder.** Confirm the API shapes above and the folder format against one real sample folder on the dev machine; record the resolved decisions.
   _Acceptance:_ a written contract and a real example folder exist and agree.
2. **Slice 1 — catalog JSON from a real scan (no images, no DB).** Scan the folder in memory; serve `GET /comics` and `GET /comics/{id}`.
   _Acceptance:_ `curl /comics` returns JSON whose comic/chapter counts match the folder on disk; a re-run is byte-identical (idempotent).
3. **Slice 2 — page images + reader endpoint.** Add `GET /comics/{id}/chapters/{cid}` (ordered page URLs) and the `/media/...` route.
   _Acceptance:_ opening a page URL in a browser shows the correct image in correct order.
4. **Slice 3 — iOS consumes it end-to-end.** Repository fetches `/comics`; swap the `HomeView` data source; three `Image → AsyncImage` sites; catalog loading/error states.
   _Acceptance:_ launch the app against the backend, see the folder's comics, open a chapter, scroll real page images, with a visible loading state and the failure placeholder when the server is down.
5. **Slice 4 — reading-position persistence (the DB's real trigger).** Introduce **PostgreSQL** (decided 2026-07-23) for a single `progress` table only; the catalog stays scan-derived; the contract's `readState` / `lastReadAt` become live and the reader gains `lastReadPage`, all keyed on the stable IDs. The stack becomes a **Docker Compose** of two services (`api`, `postgres`); the iOS reader tracks the visible page and reports it (debounced) via `PUT .../progress`, and resumes with `ScrollViewReader`.
   _Acceptance:_ read part of a chapter (page K), restart the app/backend, and resume at ~page K with the chapter shown as `reading`.

Redis is considered only after this, if there is a real job for it (multiple workers sharing a cached catalog, or measured slowness) — behind the unchanged API contract, as a third Compose service.

### Slice 4 storage detail

- **Engine: PostgreSQL** (not SQLite). A single `progress` table, keyed on the stable path-hash IDs:
  `(comic_id, chapter_id)` primary key, `last_page INT`, `page_count INT`, `updated_at TIMESTAMPTZ`.
- **Access: SQLAlchemy 2.0 + psycopg (sync)** to match the existing sync FastAPI handlers. Table created with `CREATE TABLE IF NOT EXISTS` at startup — **no Alembic** for one table (minimum architecture).
- **Config: `DATABASE_URL`** lives only in the gitignored `.env`, alongside `MANGA_LIBRARY_PATH`; never committed.
- **Container topology:** `docker-compose.yml` runs `api` (FastAPI/uvicorn; the manga folder **read-only bind-mounted** into the container, e.g. host `$MANGA_LIBRARY_PATH` → `/library`; port 8000 published) and `postgres` (named volume for data). `/media` URLs still derive from `request.base_url`, so a published port needs no code change.
- **Catalog stays scan-derived.** The DB stores only folder-external state (progress). Because the IDs are path-derived and stable, a rescan/restart preserves the join between catalog and progress.
- **Tests** run against a throwaway database/schema (not the dev progress DB): upsert idempotency, the three `readState` boundaries (no row / partial / `last_page == page_count`), `lastReadAt` aggregation, unknown chapter → 404, out-of-range page → 422, and progress surviving a rescan.

## Decisions

Confirmed (2026-07-22):

- Folder format, nesting, and chapter-name parsing — as in "Folder format" above.
- Cover rule — `cover.*` else the first page of the first chapter.
- Extensions `.jpg/.jpeg/.png/.webp`; natural sort.
- API framework — FastAPI + uvicorn (Python).
- ID scheme — stable hash of the item's relative path (load-bearing).
- `Models.swift` image fields (`coverImageName`, `pageImageNames`) — retype to `URL`.
- Storage ordering — scan-and-serve in-memory first; **not** DB-first (see "Storage: why not build the database first?"). PostgreSQL arrives at Slice 4 for reading progress.

Confirmed (2026-07-23):

- Slice-4 persistence engine — **PostgreSQL** (not SQLite), accessed via SQLAlchemy 2.0 + psycopg (sync), single `progress` table, `CREATE TABLE IF NOT EXISTS` (no Alembic).
- Reading-progress granularity — **page-level** (resume at the saved page within a chapter), keyed on the stable IDs.
- Container topology — **Docker Compose, two services (`api` + `postgres`)**; manga folder read-only bind-mounted into `api`. **Redis deferred** with a written trigger (see the components table): only when multiple workers must share a cached catalog, or measured slowness.
- Connectivity for a stable public endpoint — **Cloudflare Tunnel** (named tunnel + own domain), no Access policy for now; all infra stays local, nothing hosted in the cloud.

Open:

- (none blocking Slice 4)

## Scope notes

- This **expands `PLAN.md` scope**: backend/import are currently listed as temporarily out of scope. Record the expansion in `PLAN.md` before implementation (CLAUDE.md source-of-truth rule).
- Folder import is a **developer content pipeline**, distinct from `README.md` Roadmap §2 (URL/legal-source import). It is a way to feed real data during development, not the eventual product import path.

## Agent workflow

The main Claude Code session drives the process and owns integration.

1. Use `/research` (or the Explore agent) to clarify one unclear service or decision.
2. Capture an approved scope, file boundary, acceptance criteria, and verification expectation in the active `.scratch/<feature>/` ticket.
3. Delegate one implementer for one increment: `backend-implementer` for `backend/` work, `frontend-implementer` for iOS/SwiftUI work. The main session decides, integrates, and reports progress; it does not implement. Shared-contract changes (e.g. `Shared/Models.swift`) are delegated with an explicit grant.
4. Run `/code-review` after the increment is complete.
5. Integrate confirmed findings and update the `.scratch/` ticket from evidence.

Do not let multiple implementers edit the same files concurrently. Parallel work is reserved for independent research or stable, non-overlapping contracts.
