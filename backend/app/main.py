"""FastAPI application: scan the manga library on startup and serve the catalog.

Endpoints (see docs/backend-architecture.md):
    GET  /comics                               -> [ { id, title, coverUrl, ... } ]
    GET  /comics/{comicId}                     -> { id, title, coverUrl, chapters }
    GET  /comics/{comicId}/chapters/{chapterId}-> { id, number, title, pages }
    GET  /media/{comicId}/{chapterId}/{page}   -> image bytes (1-based page index)
    GET  /media/{comicId}/cover                -> cover image bytes
    POST   /comprehensions                     -> enqueue one record, returned as "pending"
    GET    /comprehensions                     -> list every record, newest first ("歷史紀錄")
    GET    /comprehensions/{id}                -> one record (the result screen polls this)
    PATCH  /comprehensions/{id}                -> set one record's read flag
    POST   /comprehensions/{id}/retry          -> re-enqueue a failed record
    DELETE /comprehensions/{id}                -> delete one record

The comprehension work is deferred: POST /comprehensions only enqueues, and the
worker (comprehension_worker) calls Claude on its own. The app never uploads an
image and never calls Claude itself.

Also provides:
    GET  /healthz           -> liveness + catalog size
    POST /rescan            -> manual re-scan hook (optional per the doc)

Media is served read-only: every request re-resolves the joined filesystem path
and requires it to stay under the library root before streaming (see _safe_file).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager, contextmanager
from datetime import date
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse
from sqlalchemy.exc import OperationalError, SQLAlchemyError

from . import (
    comprehend_usage_store,
    comprehension_store,
    learning_card_store,
    progress_store,
)
from .comprehension_worker import ComprehensionWorker
from .config import get_library_root
from .db import (
    ComprehensionRecord,
    LearningCard,
    init_engine,
    new_session,
    upgrade_schema,
)
from .models import (
    ChapterDetail,
    ChapterSummary,
    ComicDetail,
    ComicSummary,
    ComprehensionRecordCreate,
    ComprehensionRecordReadUpdate,
    ComprehensionRecordResponse,
    LearningCardCreate,
    LearningCardResponse,
    LearningCardUpdate,
    ProgressResponse,
    ProgressUpdate,
)
from .normalization import normalized_key
from .scanner import Catalog, ChapterEntry, ComicEntry, scan_library

# Map a file extension (lowercased, with dot) to the Content-Type we serve.
# Only the accepted page extensions are here; anything else never reaches the
# media route because the scanner does not store non-image paths.
_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vista_comic.api")


class AppState:
    """Holds the current in-memory catalog. Rebuilt on startup / rescan."""

    catalog: Catalog | None = None


state = AppState()


def load_catalog(root: Path) -> Catalog:
    """Scan ``root`` (read-only) and install the result as the live catalog.

    Exposed so tests can back the app with a temporary fixture library instead
    of the configured ``MANGA_LIBRARY_PATH``.
    """
    logger.info("Scanning library (read-only)...")
    catalog = scan_library(root)
    state.catalog = catalog
    return catalog


def _rescan() -> Catalog:
    return load_catalog(get_library_root())


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Connect to Postgres and ensure the progress table exists (CREATE TABLE IF
    # NOT EXISTS) before serving. The catalog stays scan-derived; the DB holds
    # only folder-external reading progress. A DB outage must NOT take down
    # catalog browsing, so a failed init is logged and the app still starts —
    # progress reads degrade to "no progress" until the DB is reachable and the
    # API is restarted.
    #
    # Two failures, deliberately handled differently:
    #
    # - The database is unreachable (`OperationalError`). An outage must not
    #   take browsing down — the catalog is scanned from disk and never needed
    #   Postgres — so this is logged and serving continues, with progress and
    #   history degraded until the database is back and the API is restarted.
    # - Anything else means the migration itself would not apply: the schema is
    #   not what this code expects. Serving through that only moves the error
    #   somewhere further from its cause, so it propagates and the container
    #   fails to start.
    try:
        init_engine()
        upgrade_schema()
    except OperationalError:
        logger.warning(
            "Database unreachable at startup; serving the catalog without "
            "reading progress or history until it is reachable and the API is "
            "restarted.",
            exc_info=True,
        )
    _rescan()
    # Start draining the comprehension queue. Started after the scan so the
    # worker can always resolve a record's page, and after `init_engine` so it
    # has a store to claim from. Releasing orphaned claims happens inside
    # `start()`, before the loop begins.
    worker = ComprehensionWorker(page_path_for=page_file_path)
    worker.start()
    try:
        yield
    finally:
        worker.stop()


app = FastAPI(title="vista_comic backend", version="0.1.0", lifespan=lifespan)


def _require_catalog() -> Catalog:
    # The lifespan handler fails fast at boot if the scan cannot complete, so a
    # started server always has a catalog. This 503 is a defensive guard for the
    # unreachable case where the catalog is somehow absent (e.g. a caller that
    # bypassed lifespan); it should never fire in normal operation.
    if state.catalog is None:
        raise HTTPException(status_code=503, detail="Catalog not loaded")
    return state.catalog


def _base_url(request: Request) -> str:
    """Absolute origin for building media URLs (no trailing slash).

    Derived from the incoming request so the same server works on any host/port
    (localhost, LAN IP, or a tunnel) without hardcoding an origin.
    """
    return str(request.base_url).rstrip("/")


def _cover_url(base: str, comic_id: str) -> str:
    """Absolute cover URL using the opaque comic ID.

    The shape uses the stable ID (not a raw folder name) to avoid path-encoding
    / traversal, and matches the page URL shape so the app configures one base.
    """
    return f"{base}/media/{comic_id}/cover"


def _chapter_cover_url(base: str, comic_id: str, chapter: ChapterEntry) -> str:
    """What a chapter row should show.

    Its own ``cover.*`` where it has one, otherwise the comic's cover. The
    fallback is deliberately not the chapter's first page: the app has already
    loaded the comic's cover for the library card and the chapter screen's
    header, so borrowing it costs nothing, where a full-resolution manga page
    behind a 60-point thumbnail costs a download per row.
    """
    if chapter.cover_path is not None:
        return f"{base}/media/{comic_id}/{chapter.id}/cover"
    return _cover_url(base, comic_id)


def _page_url(base: str, comic_id: str, chapter_id: str, index_1based: int) -> str:
    """Absolute page URL. The selector is a 1-based page index (see media route)."""
    return f"{base}/media/{comic_id}/{chapter_id}/{index_1based}"


def _content_type_for(rel_path: str) -> str:
    return _CONTENT_TYPES.get(Path(rel_path).suffix.lower(), "application/octet-stream")


def _safe_file(catalog: Catalog, rel_path: str) -> Path:
    """Resolve a stored relative path to a real file under the library root.

    Load-bearing security guard: join the stored path onto the root, resolve
    symlinks/``..``, and REQUIRE the result to stay under the resolved root.
    Anything escaping (symlink target outside, ``..`` traversal) or missing is
    rejected with 404 and never served. Read-only: the file is only opened for
    reading by ``FileResponse``.
    """
    root_real = catalog.root.resolve()
    candidate = (catalog.root / rel_path).resolve()
    if not candidate.is_relative_to(root_real):
        raise HTTPException(status_code=404, detail="Not found")
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return candidate


def page_file_path(comic_id: str, chapter_id: str, page_number: int) -> Optional[Path]:
    """Resolve one page to a real file under the library root, or ``None``.

    The non-HTTP half of what the media route does, so the comprehension worker
    can re-read a page minutes after it was enqueued using only the ids stored
    on the record. That re-derivability is why no image is ever stored: the
    library is the only copy.

    Returns ``None`` rather than raising for "not in the catalog" (unknown ids,
    a page index past the end) so the caller can treat a vanished comic as an
    ordinary outcome. ``_safe_file``'s containment check still applies, and it
    still raises -- a path escaping the library root is not an ordinary outcome.
    """
    catalog = state.catalog
    if catalog is None:
        return None
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        return None
    chapter = catalog.chapters_by_id.get(chapter_id)
    if chapter is None or chapter not in comic.chapters:
        return None
    if page_number < 1 or page_number > chapter.page_count:
        return None
    return _safe_file(catalog, chapter.page_paths[page_number - 1])


def _to_summary(
    base: str,
    comic: ComicEntry,
    last_read_at: str | None,
    continue_chapter_id: str,
) -> ComicSummary:
    return ComicSummary(
        id=comic.id,
        title=comic.title,
        coverUrl=_cover_url(base, comic.id),
        chapterCount=comic.chapter_count,
        lastReadAt=last_read_at,
        continueChapterId=continue_chapter_id,
    )


@app.get("/healthz")
def healthz() -> dict:
    catalog = _require_catalog()
    return {
        "status": "ok",
        "comics": len(catalog.comics),
        "chapters": sum(c.chapter_count for c in catalog.comics),
    }


@app.get("/comics", response_model=list[ComicSummary])
def list_comics(request: Request) -> list[ComicSummary]:
    catalog = _require_catalog()
    base = _base_url(request)
    # One grouped query for the whole list: comic_id -> {chapter_id -> Progress}.
    # Both lastReadAt (max updated_at per comic) and continueChapterId are
    # derived from it — no N+1, no second query. Degrades to {} if the progress
    # store is unavailable: lastReadAt null, continueChapterId -> first chapter.
    progress = progress_store.safe_all_progress()
    result = []
    for c in catalog.comics:
        rows = progress.get(c.id, {})
        last_dt = max((r.updated_at for r in rows.values()), default=None)
        result.append(
            _to_summary(
                base,
                c,
                progress_store.iso_utc(last_dt) if last_dt else None,
                progress_store.continue_chapter_id(c.chapters, rows),
            )
        )
    return result


@app.get("/comics/{comic_id}", response_model=ComicDetail)
def get_comic(comic_id: str, request: Request) -> ComicDetail:
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        raise HTTPException(status_code=404, detail="Comic not found")
    base = _base_url(request)
    # One query for this comic's rows; derive per-chapter readState.
    # Degrades to {} (all readState "unread") if the progress store is unavailable.
    rows = progress_store.safe_progress_by_chapter(comic_id)
    return ComicDetail(
        id=comic.id,
        title=comic.title,
        coverUrl=_cover_url(base, comic.id),
        chapters=[
            ChapterSummary(
                id=ch.id,
                number=ch.number,
                title=ch.title,
                pageCount=ch.page_count,
                coverUrl=_chapter_cover_url(base, comic.id, ch),
                readState=progress_store.read_state(
                    rows[ch.id].last_page if ch.id in rows else None,
                    ch.page_count,
                ),
            )
            for ch in comic.chapters
        ],
    )


@app.get(
    "/comics/{comic_id}/chapters/{chapter_id}",
    response_model=ChapterDetail,
    response_model_exclude_none=True,  # omit lastReadPage when there is no row
)
def get_chapter(
    comic_id: str,
    chapter_id: str,
    request: Request,
) -> ChapterDetail:
    """Reader endpoint: ordered absolute page URLs for one chapter.

    404 if the comic id is unknown, or if the chapter id is unknown / does not
    belong to that comic. Page URLs use a 1-based index selector so the client
    fetches exactly the array it receives. ``lastReadPage`` is the stored resume
    position, omitted when there is no progress row.
    """
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        raise HTTPException(status_code=404, detail="Comic not found")
    chapter = catalog.chapters_by_id.get(chapter_id)
    if chapter is None or chapter not in comic.chapters:
        raise HTTPException(status_code=404, detail="Chapter not found")
    base = _base_url(request)
    pages = [
        _page_url(base, comic_id, chapter_id, i + 1)
        for i in range(chapter.page_count)
    ]
    # Degrades to None (lastReadPage omitted) if the progress store is unavailable.
    row = progress_store.safe_get(comic_id, chapter_id)
    return ChapterDetail(
        id=chapter.id,
        number=chapter.number,
        title=chapter.title,
        pages=pages,
        lastReadPage=row.last_page if row is not None else None,
    )


@app.put(
    "/comics/{comic_id}/chapters/{chapter_id}/progress",
    response_model=ProgressResponse,
)
def save_progress(
    comic_id: str,
    chapter_id: str,
    body: ProgressUpdate,
) -> ProgressResponse:
    """Save a 1-based reading position for one chapter.

    404 if the comic/chapter is unknown or the chapter does not belong to the
    comic; 422 if ``lastPage`` is out of ``[1, pageCount]`` (pageCount comes from
    the catalog chapter); 503 if the progress store is unavailable. Upserts and
    echoes the saved state. Unlike the read paths, a write has no fallback — the
    caller is told the save did not happen.
    """
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        raise HTTPException(status_code=404, detail="Comic not found")
    chapter = catalog.chapters_by_id.get(chapter_id)
    if chapter is None or chapter not in comic.chapters:
        raise HTTPException(status_code=404, detail="Chapter not found")

    page_count = chapter.page_count
    if body.lastPage < 1 or body.lastPage > page_count:
        raise HTTPException(
            status_code=422,
            detail=f"lastPage must be in [1, {page_count}]",
        )

    try:
        session = new_session()
    except RuntimeError:
        # Engine never initialised (Postgres was down at startup).
        raise HTTPException(status_code=503, detail="Progress store unavailable")
    try:
        updated_at = progress_store.upsert(
            session, comic_id, chapter_id, body.lastPage, page_count
        )
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Progress store write failed.", exc_info=True)
        raise HTTPException(status_code=503, detail="Progress store unavailable")
    finally:
        session.close()
    return ProgressResponse(
        comicId=comic_id,
        chapterId=chapter_id,
        lastPage=body.lastPage,
        pageCount=page_count,
        updatedAt=progress_store.iso_utc(updated_at),
    )


# ---------------------------------------------------------------------------
# Comprehension records (comprehension-response-ux): the 歷史紀錄 store, whose
# rows double as the work queue a worker drains. This resource replaced
# /translations and /comprehend, both removed in the removal ticket along with
# a manual `DROP TABLE saved_translation` (see docs/manual-migrations.md).
# ---------------------------------------------------------------------------


_COMPREHENSION_STORE_UNAVAILABLE = "Comprehension store unavailable"


@contextmanager
def _store_session(unavailable_detail: str, failure_log: str):
    """Yield a session for one store operation, or 503.

    Extracted because six comprehension routes needed the identical
    open/rollback/close dance, which the superseded ``/translations`` routes used
    to repeat inline three times -- a shape that does not survive doubling. The
    ``/cards`` routes are the third resource to want it, which is why the detail
    string is a parameter now rather than a constant.

    A store that was never initialised and one that fails mid-request both
    surface as 503, because these rows have no independent origin to fall back
    on -- reporting "unreachable" as "you have no history" (or "your vocabulary
    is empty") would be a lie the reader cannot detect.

    Only ``SQLAlchemyError`` is converted; an ``HTTPException`` raised by the
    body (a 404, say) passes through untouched.
    """
    try:
        session = new_session()
    except RuntimeError:
        raise HTTPException(status_code=503, detail=unavailable_detail)
    try:
        yield session
    except SQLAlchemyError:
        session.rollback()
        logger.warning(failure_log, exc_info=True)
        raise HTTPException(status_code=503, detail=unavailable_detail)
    finally:
        session.close()


@contextmanager
def _comprehension_session():
    """A store session whose failures are reported as the history store's."""
    with _store_session(
        _COMPREHENSION_STORE_UNAVAILABLE, "Comprehension store operation failed."
    ) as session:
        yield session


def _titles_for(comic_id: str, chapter_id: str) -> tuple[Optional[str], Optional[str]]:
    """Resolve display titles for a record's source, or ``(None, None)``.

    Joined from the in-memory catalog at read time rather than stored on the
    row: the record holds path-hash ids, which are correct as keys and useless
    as labels (see ``ids.stable_id``). Joining also means a renamed comic shows
    its new title everywhere, with nothing to migrate.

    Reads ``state.catalog`` directly instead of ``_require_catalog`` on purpose.
    Titles are decoration; the records are the data. A reader must still be able
    to browse their history when the library scan is unavailable, so a missing
    catalog degrades the labels rather than failing the request. ``None`` is also
    the client's cue that jumping to the source page would fail.
    """
    catalog = state.catalog
    if catalog is None:
        return None, None
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        return None, None
    chapter = next((ch for ch in comic.chapters if ch.id == chapter_id), None)
    return comic.title, (chapter.title if chapter is not None else None)


def _to_comprehension_response(row: ComprehensionRecord) -> ComprehensionRecordResponse:
    comic_title, chapter_title = _titles_for(row.comic_id, row.chapter_id)
    return ComprehensionRecordResponse(
        id=row.id,
        sourceText=row.source_text,
        translatedText=row.translated_text,
        cloudTranslation=row.cloud_translation,
        grammarNotes=row.grammar_notes,
        contextNotes=row.context_notes,
        toneRegister=row.tone_register,
        targetLanguage=row.target_language,
        comicId=row.comic_id,
        chapterId=row.chapter_id,
        pageNumber=row.page_number,
        comicTitle=comic_title,
        chapterTitle=chapter_title,
        status=row.status,
        isRead=row.is_read,
        useStrongerModel=row.use_stronger_model,
        createdAt=progress_store.iso_utc(row.created_at),
    )


@app.post("/comprehensions", response_model=ComprehensionRecordResponse, status_code=201)
def create_comprehension(body: ComprehensionRecordCreate) -> ComprehensionRecordResponse:
    """Enqueue one comprehension record and return it immediately as ``pending``.

    Returns without waiting for Claude: the reader already has the on-device
    translation in ``translatedText`` and the explanation arrives later, which
    is the entire point of this resource.

    The daily cap is **reserved here**, not when the worker actually calls
    Claude, for two reasons: an exhausted cap can be reported to the reader at
    the moment they act (429, and no row is created, so nothing appears in their
    history that will never complete), and the queue can never grow longer than
    the remaining budget. The reserved date is stored on the row (see
    ``comprehend_usage_store.refund``).

    The reservation is given back if the row is not actually created -- a
    reserved-but-unspent request must not silently burn budget just because the
    store was unreachable.
    """
    usage_date = _reserve_daily_cap()
    try:
        with _comprehension_session() as session:
            row = comprehension_store.insert_record(
                session,
                source_text=body.sourceText,
                translated_text=body.translatedText,
                target_language=body.targetLanguage,
                comic_id=body.comicId,
                chapter_id=body.chapterId,
                page_number=body.pageNumber,
                use_stronger_model=body.useStrongerModel,
                usage_date=usage_date,
            )
    except HTTPException:
        _refund_daily_cap(usage_date)
        raise
    return _to_comprehension_response(row)


@app.get("/comprehensions", response_model=list[ComprehensionRecordResponse])
def list_comprehensions() -> list[ComprehensionRecordResponse]:
    """Every record, newest first -- the 歷史紀錄 list and its unread badge."""
    with _comprehension_session() as session:
        rows = comprehension_store.list_all(session)
    return [_to_comprehension_response(row) for row in rows]


@app.get("/comprehensions/{record_id}", response_model=ComprehensionRecordResponse)
def get_comprehension(record_id: int) -> ComprehensionRecordResponse:
    """One record -- the result screen polls this while its record is unfinished."""
    with _comprehension_session() as session:
        row = comprehension_store.get(session, record_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Comprehension record not found")
    return _to_comprehension_response(row)


@app.patch("/comprehensions/{record_id}", response_model=ComprehensionRecordResponse)
def update_comprehension(
    record_id: int, body: ComprehensionRecordReadUpdate
) -> ComprehensionRecordResponse:
    """Set one record's read flag -- opening it in 歷史紀錄 marks it read.

    Only the read flag is patchable; status transitions are not client-driven,
    so re-running a record is its own endpoint with its own precondition. Both
    boolean values are honoured rather than only ``true``: the reader clears the
    badge by opening an entry, and a boolean field that silently refuses one of
    its two values is a worse contract than one that simply works.
    """
    with _comprehension_session() as session:
        found = comprehension_store.set_read(session, record_id, is_read=body.isRead)
        row = comprehension_store.get(session, record_id) if found else None
    if row is None:
        raise HTTPException(status_code=404, detail="Comprehension record not found")
    return _to_comprehension_response(row)


@app.post(
    "/comprehensions/{record_id}/retry", response_model=ComprehensionRecordResponse
)
def retry_comprehension(record_id: int) -> ComprehensionRecordResponse:
    """Re-enqueue a ``failed`` record for another attempt.

    Its own endpoint rather than a status-setting PATCH: re-running is a domain
    action with a precondition (only ``failed`` qualifies) and a cost (another
    cap reservation), and exposing arbitrary status transitions would leak the
    state machine to the client.

    409 rather than 404 when the record exists but is not ``failed`` -- retrying
    something still being produced, already explained, or declined is a
    different mistake from retrying something that isn't there, and only the
    former means "look again in a moment".

    Every path that does not actually re-enqueue gives the reservation back.
    """
    usage_date = _reserve_daily_cap()
    try:
        with _comprehension_session() as session:
            row = comprehension_store.requeue_failed(
                session, record_id, usage_date=usage_date
            )
            existed = row is not None or comprehension_store.get(session, record_id) is not None
    except HTTPException:
        _refund_daily_cap(usage_date)
        raise
    if row is None:
        _refund_daily_cap(usage_date)
        if existed:
            raise HTTPException(
                status_code=409, detail="Only a failed record can be retried"
            )
        raise HTTPException(status_code=404, detail="Comprehension record not found")
    return _to_comprehension_response(row)


@app.delete("/comprehensions/{record_id}", status_code=204, response_model=None)
def delete_comprehension(record_id: int) -> None:
    """Delete one record, refunding its reservation if it never reached Claude.

    A ``pending`` row has been paid for but not spent, so deleting it returns
    the request to the day it was reserved against. A row that has already run
    keeps its count -- including a declined one, which produced billable tokens.
    """
    with _comprehension_session() as session:
        deleted = comprehension_store.delete_record(session, record_id)
    if deleted is None:
        raise HTTPException(status_code=404, detail="Comprehension record not found")
    if deleted.status == comprehension_store.STATUS_PENDING:
        _refund_daily_cap(deleted.usage_date)


def _refund_daily_cap(usage_date: date) -> None:
    """Return one reserved-but-unspent request to ``usage_date``'s count.

    Best-effort by design: a failed refund is logged and swallowed. The refund
    exists to keep an anomaly guard honest, and letting a bookkeeping problem
    turn an otherwise-successful delete into an error for the reader would trade
    a real failure for a cosmetic one.
    """
    try:
        session = new_session()
    except RuntimeError:
        return
    try:
        comprehend_usage_store.refund(session, usage_date=usage_date)
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Comprehension usage refund failed.", exc_info=True)
    finally:
        session.close()


def _reserve_daily_cap() -> date:
    """Reserve one request against the global daily cap; 429 once it's reached.

    Returns the UTC date the reservation was taken against, so the caller can
    store it on the row it creates and any later refund goes back to *that* day
    rather than to whatever day it happens to be when the refund runs.

    Global, not per-user -- this backend has no per-user identity (a single
    shared Cloudflare Access Service Token gates every request, see
    ADR-0005) -- purely an anomaly guard (e.g. against a retry-loop bug)
    against runaway Claude spend, not real usage-limiting.

    Fails CLOSED (503) on a genuine store failure once a session was
    obtained (``SQLAlchemyError`` -- e.g. the DB connection drops mid-request):
    this guard exists specifically for cost protection, so "can't verify the
    cap" must not silently become "allow anyway", unlike the read-side
    catalog/progress helpers (``progress_store.safe_*``) that intentionally
    degrade for availability.

    Fails OPEN only when the engine was never initialized at all
    (``new_session()``'s ``RuntimeError``). In the real deployed app this
    cannot happen once serving has started: the lifespan handler always calls
    ``init_engine()``, which assigns the module-level engine/session-factory
    globals even when the subsequent ``CREATE TABLE`` probe fails against a
    genuinely-down Postgres (see ``db.init_engine`` -- ``_engine``/
    ``_SessionLocal`` are set before ``create_all`` runs). A live-but-
    unreachable DB therefore surfaces as ``SQLAlchemyError``, handled by the
    fail-closed branch above, not as ``RuntimeError``. The ``RuntimeError``
    branch is reachable only through a test harness that builds
    ``TestClient(app)`` without running the startup lifespan (as
    ``test_comprehension.py``'s ticket-11 tests already do), so it degrades
    the same way ``progress_store``'s read-side helpers already do for "store
    never initialized", rather than rejecting every comprehension request
    over a codepath that cannot occur once the app has actually started.
    """
    usage_date = comprehend_usage_store.today_utc()
    try:
        session = new_session()
    except RuntimeError:
        logger.warning(
            "Comprehension usage store not initialized; allowing the request "
            "without a daily-cap check."
        )
        return usage_date
    try:
        allowed = comprehend_usage_store.check_and_increment(
            session, cap=comprehend_usage_store.DAILY_CAP, today=usage_date
        )
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Comprehension usage store unavailable.", exc_info=True)
        raise HTTPException(
            status_code=503, detail="Comprehension usage store unavailable"
        )
    finally:
        session.close()
    if not allowed:
        raise HTTPException(
            status_code=429, detail="Daily comprehension request cap reached"
        )
    return usage_date


@app.get("/media/{comic_id}/{chapter_id}/cover")
def get_chapter_cover_image(comic_id: str, chapter_id: str) -> FileResponse:
    """Stream a chapter's own ``cover.*``.

    Declared before the page route below, which would otherwise match ``cover``
    as its ``{page}`` selector and 404 on the int parse.

    404 when the chapter has no cover of its own: the app is told which chapters
    have one (see the ``coverUrl`` on each chapter summary) and asks for the
    comic's cover instead, so reaching here without one means a stale client or
    a hand-typed URL.
    """
    catalog = _require_catalog()
    chapter = catalog.chapters_by_id.get(chapter_id)
    if chapter is None or chapter.cover_path is None:
        raise HTTPException(status_code=404, detail="Not found")
    file_path = _safe_file(catalog, chapter.cover_path)
    return FileResponse(file_path, media_type=_content_type_for(chapter.cover_path))


@app.get("/media/{comic_id}/{chapter_id}/{page}")
def get_page_image(comic_id: str, chapter_id: str, page: str) -> FileResponse:
    """Stream one page image by 1-based index.

    ``page`` is a 1-based index into the chapter's ordered ``page_paths`` (the
    same order as the reader endpoint's ``pages`` array). Non-integer or
    out-of-range selectors, and unknown ids, return 404. The resolved file path
    is re-validated to stay under the library root before streaming.
    """
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        raise HTTPException(status_code=404, detail="Not found")
    chapter = catalog.chapters_by_id.get(chapter_id)
    if chapter is None or chapter not in comic.chapters:
        raise HTTPException(status_code=404, detail="Not found")

    try:
        index_1based = int(page)
    except ValueError:
        raise HTTPException(status_code=404, detail="Not found")
    if index_1based < 1 or index_1based > chapter.page_count:
        raise HTTPException(status_code=404, detail="Not found")

    rel_path = chapter.page_paths[index_1based - 1]
    file_path = _safe_file(catalog, rel_path)
    return FileResponse(file_path, media_type=_content_type_for(rel_path))


@app.get("/media/{comic_id}/cover")
def get_cover_image(comic_id: str) -> FileResponse:
    """Stream a comic's resolved cover (explicit ``cover.*`` or fallback page).

    ``cover_path`` was resolved at scan time to either an explicit ``cover.*``
    file or the first page of the lowest-numbered chapter; both are handled the
    same way here. Unknown comic / no resolvable cover returns 404.
    """
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None or comic.cover_path is None:
        raise HTTPException(status_code=404, detail="Not found")
    file_path = _safe_file(catalog, comic.cover_path)
    return FileResponse(file_path, media_type=_content_type_for(comic.cover_path))


@app.post("/rescan")
def rescan() -> dict:
    """Manually rebuild the in-memory catalog from the folder (read-only)."""
    catalog = _rescan()
    return {
        "status": "rescanned",
        "comics": len(catalog.comics),
        "chapters": sum(c.chapter_count for c in catalog.comics),
    }


# ---------------------------------------------------------------------------
# Learning cards (vocabulary-review stage 1): the 單字庫 store. A row exists
# only because the reader pressed add, having read the source text and the
# translation and judged them right — see .scratch/vocabulary-review/prd.md.
# ---------------------------------------------------------------------------


_CARD_STORE_UNAVAILABLE = "Vocabulary store unavailable"


@contextmanager
def _card_session():
    """A store session whose failures are reported as the vocabulary store's."""
    with _store_session(
        _CARD_STORE_UNAVAILABLE, "Vocabulary store operation failed."
    ) as session:
        yield session


def _to_card_response(row: LearningCard) -> LearningCardResponse:
    # Same join, same function, same degradation as the history rows: titles are
    # decoration and the cards are the data, so an unavailable catalog costs the
    # labels rather than the request.
    comic_title, chapter_title = _titles_for(row.comic_id, row.chapter_id)
    return LearningCardResponse(
        id=row.id,
        sourceText=row.source_text,
        translation=row.translation,
        targetLanguage=row.target_language,
        comicId=row.comic_id,
        chapterId=row.chapter_id,
        pageNumber=row.page_number,
        comicTitle=comic_title,
        chapterTitle=chapter_title,
        kind=row.kind,
        ladderStage=row.ladder_stage,
        dueOn=row.due_on.isoformat(),
        lookupCount=row.lookup_count,
        lastLookedUpAt=(
            progress_store.iso_utc(row.last_looked_up_at)
            if row.last_looked_up_at is not None
            else None
        ),
        createdAt=progress_store.iso_utc(row.created_at),
    )


@app.post("/cards", response_model=LearningCardResponse, status_code=201)
def create_card(body: LearningCardCreate, response: Response) -> LearningCardResponse:
    """Collect one line. 201 when it is new, **200 when it was already there**.

    Idempotent rather than conflicting, because the app queues what it could not
    send while offline and replays the queue blindly on reconnect. A replay is
    the expected case, not a client error, so answering 409 would turn normal
    operation into something the client has to special-case.

    Text that normalises to nothing is refused here rather than in the model:
    the length cap cannot catch a string of spaces, and storing a card with an
    empty identity would collide with every other empty one.
    """
    if not normalized_key(body.sourceText):
        raise HTTPException(
            status_code=422, detail="sourceText contains nothing to learn"
        )
    with _card_session() as session:
        row, created = learning_card_store.create_or_get(
            session,
            source_text=body.sourceText,
            translation=body.translation,
            target_language=body.targetLanguage,
            comic_id=body.comicId,
            chapter_id=body.chapterId,
            page_number=body.pageNumber,
            kind=body.kind,
        )
    if not created:
        response.status_code = 200
    return _to_card_response(row)


@app.get("/cards", response_model=list[LearningCardResponse])
def list_cards() -> list[LearningCardResponse]:
    """Every card the reader still has, newest first.

    Unpaginated on purpose: this is one person's hand-picked vocabulary, and the
    app caches the whole response as the snapshot it matches against offline.
    Paginating it would mean the snapshot is a guess about which page mattered.
    """
    with _card_session() as session:
        rows = learning_card_store.list_active(session)
    return [_to_card_response(row) for row in rows]


@app.patch("/cards/{card_id}", response_model=LearningCardResponse)
def update_card(card_id: int, body: LearningCardUpdate) -> LearningCardResponse:
    """Correct what the reader is allowed to correct: the translation, the kind.

    Two fields, and the refusal of everything else is deliberate — the identity
    columns and the source reference are not the client's to move (see
    ``models.LearningCardUpdate``).

    ``kind`` is read from ``model_fields_set`` rather than by testing for
    ``None``, because clearing a kind is a real thing to want: a card collected
    before the two save buttons existed has none, and a mis-tapped one is
    corrected here since re-collecting deliberately leaves it alone.

    A body that changes nothing is refused rather than answered with a
    no-op, so a client bug shows up as an error instead of as a save that
    quietly did not happen.
    """
    fields = body.model_fields_set
    if not fields:
        raise HTTPException(
            status_code=422, detail="Provide translation, kind, or both"
        )

    with _card_session() as session:
        found = learning_card_store.update(
            session,
            card_id,
            translation=body.translation,
            kind=body.kind,
            set_kind="kind" in fields,
        )
        row = learning_card_store.get(session, card_id) if found else None
    if row is None:
        raise HTTPException(status_code=404, detail="Learning card not found")
    return _to_card_response(row)


@app.delete("/cards/{card_id}", status_code=204)
def delete_card(card_id: int) -> Response:
    """Remove one card. A real delete, not a flag — see ``learning_card_store``."""
    with _card_session() as session:
        deleted = learning_card_store.delete(session, card_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Learning card not found")
    return Response(status_code=204)


@app.post("/cards/{card_id}/lookups", status_code=204)
def record_card_lookup(card_id: int) -> Response:
    """Note that the reader looked an already-collected word up again.

    The cleanest forgetting signal this system gets: they just proved they had
    not retained it. Only the positive is recorded — *not* looking a word up
    again says nothing, since the reader may simply not have reached that page.

    Its own endpoint rather than a PATCH, because the client is reporting an
    event rather than proposing a value, and the count is not something it is
    allowed to set.
    """
    with _card_session() as session:
        found = learning_card_store.record_lookup(session, card_id)
    if not found:
        raise HTTPException(status_code=404, detail="Learning card not found")
    return Response(status_code=204)
