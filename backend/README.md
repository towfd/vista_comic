# vista_comic backend (M5)

A small "scan-and-serve" API. On startup it walks a local manga library folder
into an **in-memory catalog** and serves JSON that maps 1:1 to the iOS `Comic` /
`Chapter` models, plus the page/cover image bytes. The library is **read-only**
(the folder is the source of truth); the only writable state is reading progress,
kept in a small PostgreSQL `progress` table.

Contract of record: [`../docs/backend-architecture.md`](../docs/backend-architecture.md).

## What the API does (through M5 Slice 4)

- Scans `MANGA_LIBRARY_PATH` on startup (and on manual `POST /rescan`).
- Serves:
  - `GET /comics` → `[ { id, title, coverUrl, chapterCount, lastReadAt } ]`
  - `GET /comics/{comicId}` → `{ id, title, coverUrl, chapters: [ { id, number, title, pageCount, readState } ] }`
  - `GET /comics/{comicId}/chapters/{chapterId}` → `{ id, number, title, pages: [imageUrl…], lastReadPage? }`
  - `GET /media/{comicId}/{chapterId}/{page}` and `GET /media/{comicId}/cover` → image bytes
  - `PUT /comics/{comicId}/chapters/{chapterId}/progress` `{ "lastPage": N }` → save a 1-based reading position
  - `GET /healthz`, `POST /rescan` (operational helpers)
- `readState` / `lastReadAt` / `lastReadPage` are derived live from the `progress`
  store. The **catalog is independent of the database**: if Postgres is down,
  browsing and the reader still work (progress reads degrade to "no progress");
  only a `PUT .../progress` fails, with `503`.

## Configuration

Machine-specific config and secrets live **only** in the repo-root, gitignored
`.env` (loaded via `python-dotenv`, or read from the environment). Never
hardcoded or committed:

```
# Absolute path to the manga library folder (required).
MANGA_LIBRARY_PATH=/absolute/path/to/your/manga/library

# PostgreSQL reading-progress store. Optional for local dev — if unset it
# defaults to postgresql+psycopg://vista:vista@localhost:5432/vista (matching the
# Compose Postgres published on localhost). Set a real POSTGRES_PASSWORD for
# anything beyond throwaway local use, and mirror it here.
# DATABASE_URL=postgresql+psycopg://vista:yourpassword@localhost:5432/vista
# POSTGRES_USER=vista
# POSTGRES_PASSWORD=vista
# POSTGRES_DB=vista

# Test database (optional). Tests refuse to run unless the DB name ends in
# `_test`, and never fall back to DATABASE_URL, so they can't touch the dev DB.
# TEST_DATABASE_URL=postgresql+psycopg://vista:vista@localhost:5432/vista_test
```

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

## Run it with Docker (one command)

The repo-root `docker-compose.yml` runs the stack: an **`api`** service and a
**`postgres`** service. It reads the gitignored repo-root `.env` for
`${MANGA_LIBRARY_PATH}` and bind-mounts that host folder **read-only** at
`/library` (the container scans `/library`, set via the service's
`environment:`). `api` waits for Postgres to be healthy and connects with an
in-container `DATABASE_URL` pointing at host `postgres`; the named volume
`pg_data` persists reading progress across restarts.

From the repository root:

```bash
# Sanity-check that ${MANGA_LIBRARY_PATH} resolves (no unresolved variables):
docker compose config

# Build and start both services in the background:
docker compose up --build -d

# Health + catalog counts:
curl -s http://127.0.0.1:8000/healthz | python3 -m json.tool
curl -s http://127.0.0.1:8000/comics | python3 -m json.tool

# Save and read back reading progress:
curl -s -X PUT http://127.0.0.1:8000/comics/<comicId>/chapters/<chapterId>/progress \
  -H 'content-type: application/json' -d '{"lastPage": 3}'

# Stop and remove the containers (KEEP the pg_data volume — no -v):
docker compose down
```

The manga library is mounted read-only, so the container cannot modify the host
folder (the folder stays the source of truth). Postgres holds only
folder-external reading progress; Redis remains deferred (see the architecture
doc).

## Tests

```bash
cd backend
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# Requires Postgres reachable at localhost:5432 (e.g. `docker compose up -d postgres`).
# Tests run against a dedicated `vista_test` DB (auto-created) and refuse to run
# against any DB whose name does not end in `_test`, so the dev DB is safe.
pytest
```

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
│   ├── config.py         # load .env, resolve MANGA_LIBRARY_PATH + DATABASE_URL
│   ├── ids.py            # stable path-derived IDs
│   ├── models.py         # in-memory catalog + camelCase response models
│   ├── scanner.py        # read-only library scan
│   ├── db.py             # SQLAlchemy engine/session + `progress` table
│   ├── progress_store.py # reading-progress repository (upsert + resilient reads)
│   └── main.py           # FastAPI app + endpoints
├── requirements.txt
├── .gitignore
└── README.md
```
