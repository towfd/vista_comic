# vista_comic backend (M5)

A small, read-only "scan-and-serve" API. On startup it walks a local manga
library folder into an **in-memory catalog** and serves JSON that maps 1:1 to
the iOS `Comic` / `Chapter` models. No database, no image serving yet.

Contract of record: [`../docs/backend-architecture.md`](../docs/backend-architecture.md).

## What this slice (Slice 1) does

- Scans `MANGA_LIBRARY_PATH` on startup (and on manual `POST /rescan`).
- Serves:
  - `GET /comics` → `[ { id, title, coverUrl, chapterCount, lastReadAt } ]`
  - `GET /comics/{comicId}` → `{ id, title, coverUrl, chapters: [ { id, number, title, pageCount, readState } ] }`
  - `GET /healthz`, `POST /rescan` (operational helpers)
- **Not yet:** `/media/...` image bytes and the per-chapter pages endpoint (Slice 2).

## Configuration

The library path is machine-specific and lives **only** in the repo-root,
gitignored `.env`:

```
MANGA_LIBRARY_PATH=/absolute/path/to/your/manga/library
```

It is loaded automatically (via `python-dotenv`) or read from the environment.
It is never hardcoded or committed.

## Run it

From the repository root:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Start the server (reads MANGA_LIBRARY_PATH from the repo-root .env)
uvicorn app.main:app --reload --port 8000
```

Then:

```bash
curl -s http://127.0.0.1:8000/comics | python3 -m json.tool
curl -s http://127.0.0.1:8000/comics/<comicId> | python3 -m json.tool
```

To reach the API from a device/simulator on the same Wi-Fi, bind all
interfaces: `uvicorn app.main:app --host 0.0.0.0 --port 8000` and point the app
at the Mac's LAN IP (a dev ATS exception is needed for cleartext HTTP).

## Design notes

- **Stable IDs (load-bearing).** `comicId` / `chapterId` are a SHA-1 of the
  item's relative POSIX path under the library root (see `app/ids.py`). They are
  identical across scans and restarts, because Slice 4 reading-progress keys on
  them. No random UUIDs.
- **Read-only.** The scanner only lists directories and reads file metadata; it
  never writes, renames, or deletes under the library. The library is the source
  of truth.
- **`coverUrl`.** A consistent placeholder of the media-path shape
  `/media/{comicId}/cover` using the opaque ID (not a raw folder name). The
  `/media` route is implemented in Slice 2; the string shape is stable now.
- **Folder rules** (nesting, chapter-name parsing, natural page sort, cover
  resolution, hidden/unsupported-file skipping) are implemented in
  `app/scanner.py` per the contract.

## Layout

```
backend/
├── app/
│   ├── __init__.py
│   ├── config.py     # load .env, resolve MANGA_LIBRARY_PATH
│   ├── ids.py        # stable path-derived IDs
│   ├── models.py     # in-memory catalog + camelCase response models
│   ├── scanner.py    # read-only library scan
│   └── main.py       # FastAPI app + endpoints
├── requirements.txt
├── .gitignore
└── README.md
```
