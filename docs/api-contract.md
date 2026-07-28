# Backend API contract

The current shape of the vista_comic backend's contract with the iOS app. See `CONTEXT.md` for the domain vocabulary used below (Library, Comic, Chapter, Page, Catalog, Progress, Stable ID) and `docs/adr/` for why the backend is built this way.

## Folder format

Three fixed nesting levels under the Library root; everything is inferred from directory/file names — no required metadata.

```text
library/                         # the Library root (mounted / configured path)
├── Frieren/                     # Comic dir      → Comic.title = "Frieren"
│   ├── cover.jpg                # optional explicit cover
│   ├── 01 - The Journey/        # Chapter dir     → number = 1, title = "The Journey"
│   │   ├── 001.jpg              # Page 1 (natural sort; zero-pad recommended)
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

- **Nesting is exactly `library / comic / chapter / page-image`.** A dir under root is a Comic; a dir under a Comic is a Chapter; image files in a Chapter are Pages.
- **Comic title** = Comic directory name.
- **Chapter number + title** = parse the dir name as `^\s*(\d+)\s*(?:[-–_.]\s*(.*))?$` — leading integer is `number`; remainder (if any) is `title`; else `"Chapter <number>"`.
- **Page order** = natural sort of image filenames (`2` before `10`); zero-padding recommended, not required.
- **Accepted extensions**: `.jpg`, `.jpeg`, `.png`, `.webp` (case-insensitive). Others are skipped and reported.
- **Cover rule**: a `cover.*` at the Comic root if present, else the first Page (natural sort) of the lowest-numbered Chapter. Always yields a cover.
- **Metadata**: none required. Reserve an optional `info.json` (Comic, later Chapter) for future overrides (display title, author, language); schema not designed yet.
- **Malformed / hidden files** (`.DS_Store`, unsupported types): skipped, counted, reported — never crash.

## API endpoints

Shapes map 1:1 to `Comic` / `Chapter`. One origin serves both JSON and media, so the app configures a single base URL.

```text
# Library screen
GET /comics
→ [ { id, title, coverUrl, chapterCount, lastReadAt?, continueChapterId } ]

# Chapter list
GET /comics/{comicId}
→ { id, title, coverUrl,
    chapters: [ { id, number, title, pageCount, readState } ] }

# Reader
GET /comics/{comicId}/chapters/{chapterId}
→ { id, number, title,
    pages: [ "<baseUrl>/media/{comicId}/{chapterId}/001.jpg", ... ],
    lastReadPage? }              # 1-based resume position; omitted when no Progress

# Page image bytes (same origin)
GET /media/{comicId}/{chapterId}/{page}
→ image bytes (Content-Type: image/jpeg | image/png | image/webp)

# Save reading Progress
PUT /comics/{comicId}/chapters/{chapterId}/progress
   body: { "lastPage": N }       # 1-based; validated within [1, pageCount]
→ { comicId, chapterId, lastPage, pageCount, updatedAt }   # 404 unknown chapter, 422 out of range
```

Notes:

- **Images travel as URL strings the app fetches**, never embedded bytes in JSON.
- **IDs are Stable IDs** (see `CONTEXT.md`) — a hash of the item's path relative to the Library root. Path segments in `/media/...` use these opaque IDs, not raw folder names (avoids path-encoding / traversal).
- **`readState`** is derived per Chapter: no Progress row → `unread`, `lastPage >= pageCount` → `read`, else `reading`.
- **`Comic.lastReadAt`** is the max `updatedAt` across that Comic's Chapters.
- **`Comic.continueChapterId`** (always present) is the Chapter the "Continue" action opens: the most-recently-`updatedAt` `reading` Chapter, else the first `unread` Chapter in reading order, else the first Chapter. Derived from one grouped query over all Progress rows (no N+1).

## Data flow

```text
Host manga folder (source of truth)
        │  startup / manual re-scan: walk dirs, natural sort
        ▼
API scanner ──► in-memory Catalog (Comics → Chapters → ordered Page paths)
        │  HTTP JSON (Page = image URL strings)
        ▼
iOS repository ──► decodes into the same Comic / Chapter structs
        ▼
AsyncImage(url:) renders covers and pages ──► GET /media/... streams bytes from the folder
```

## Connectivity

Only the base URL the app points at (`VISTA_BASE_URL`) changes with the access method — the contract above is unaffected.

- **Same Wi-Fi:** phone/simulator → the host's LAN IP `http://192.168.x.x:PORT` (+ an ATS exception). Simulator can use `http://127.0.0.1:PORT`.
- **Stable public URL:** a Cloudflare named Tunnel (see ADR-0005) maps a hostname on a Cloudflare-managed domain to the `api` service — no port-forwarding, no static public IP, no ATS exception (HTTPS terminates at Cloudflare's edge). Only `api` is routed; `postgres` is never reachable through the tunnel.
- **Access control:** Cloudflare Access is configured on the public hostname and gates every request at Cloudflare's edge, ahead of the tunnel. The auth mechanism is a Service Token, not an interactive login: the app attaches `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers to each request; Cloudflare Access rejects requests missing valid headers before they ever reach `cloudflared` or `api`. The FastAPI app has no Access-related code — enforcement is entirely edge-side. (App-side header attachment is tracked as a follow-on ticket in `.scratch/remote-access/`.)
- In every case uvicorn / the `api` container binds `0.0.0.0`; the base URL is the only moving part.
