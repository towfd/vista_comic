"""FastAPI application: scan the manga library on startup and serve the catalog.

Endpoints (see docs/backend-architecture.md):
    GET  /comics                               -> [ { id, title, coverUrl, ... } ]
    GET  /comics/{comicId}                     -> { id, title, coverUrl, chapters }
    GET  /comics/{comicId}/chapters/{chapterId}-> { id, number, title, pages }
    GET  /media/{comicId}/{chapterId}/{page}   -> image bytes (1-based page index)
    GET  /media/{comicId}/cover                -> cover image bytes
    POST   /translations                       -> save one original/translation pair
    GET    /translations                       -> list all saved pairs ("單字本")
    DELETE /translations/{id}                  -> delete one saved pair
    POST   /comprehend                         -> translate + explain via Claude (see comprehension_client)
    POST   /comprehensions                     -> enqueue one record, returned as "pending"
    GET    /comprehensions                     -> list every record, newest first ("歷史紀錄")
    GET    /comprehensions/{id}                -> one record (the result screen polls this)
    PATCH  /comprehensions/{id}                -> set one record's read flag
    POST   /comprehensions/{id}/retry          -> re-enqueue a failed record
    DELETE /comprehensions/{id}                -> delete one record

/translations and /comprehend are superseded by /comprehensions and are removed
once the shipped client has been cut over (see docs/manual-migrations.md).

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

import anthropic
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.exc import SQLAlchemyError

from . import (
    comprehend_usage_store,
    comprehension_client,
    comprehension_store,
    progress_store,
    translation_store,
)
from .config import get_library_root
from .db import ComprehensionRecord, SavedTranslation, init_engine, new_session
from .models import (
    ChapterDetail,
    ChapterSummary,
    ComicDetail,
    ComicSummary,
    ComprehendRequest,
    ComprehendResponse,
    ComprehensionRecordCreate,
    ComprehensionRecordReadUpdate,
    ComprehensionRecordResponse,
    ProgressResponse,
    ProgressUpdate,
    SavedTranslationCreate,
    SavedTranslationResponse,
)
from .scanner import Catalog, ComicEntry, scan_library

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
    try:
        init_engine()
    except Exception:  # noqa: BLE001 — degrade gracefully; the catalog is independent
        logger.warning(
            "Progress store unavailable at startup; serving the catalog without "
            "reading progress until the database is reachable and the API is "
            "restarted.",
            exc_info=True,
        )
    _rescan()
    yield


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


def _to_translation_response(row: SavedTranslation) -> SavedTranslationResponse:
    return SavedTranslationResponse(
        id=row.id,
        originalText=row.original_text,
        translatedText=row.translated_text,
        grammarNotes=row.grammar_notes,
        contextNotes=row.context_notes,
        toneRegister=row.tone_register,
        targetLanguage=row.target_language,
        comicId=row.comic_id,
        chapterId=row.chapter_id,
        pageNumber=row.page_number,
        savedAt=progress_store.iso_utc(row.saved_at),
    )


@app.post("/translations", response_model=SavedTranslationResponse)
def save_translation(body: SavedTranslationCreate) -> SavedTranslationResponse:
    """Save one original/translated text pair with its source reference.

    503 if the store is unavailable. Unlike ``Progress``, there is no
    non-DB-backed origin for saved translations to fall back to (the catalog
    cannot reconstruct them), so this mirrors ``save_progress``'s "no
    fallback, surface the failure" behavior rather than ``progress_store``'s
    read-side degrade-to-default helpers.
    """
    try:
        session = new_session()
    except RuntimeError:
        # Engine never initialised (Postgres was down at startup).
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    try:
        row = translation_store.insert_translation(
            session,
            original_text=body.originalText,
            translated_text=body.translatedText,
            grammar_notes=body.grammarNotes,
            context_notes=body.contextNotes,
            tone_register=body.toneRegister,
            target_language=body.targetLanguage,
            comic_id=body.comicId,
            chapter_id=body.chapterId,
            page_number=body.pageNumber,
        )
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Translation store write failed.", exc_info=True)
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    finally:
        session.close()
    return _to_translation_response(row)


@app.get("/translations", response_model=list[SavedTranslationResponse])
def list_translations() -> list[SavedTranslationResponse]:
    """List every saved translation, most recently saved first ("單字本").

    503 if the store is unavailable, rather than degrading to an empty list:
    unlike the catalog (which is independently scan-derived and must survive a
    DB outage), saved translations have no origin other than this table, so an
    empty response would misrepresent "the store is down" as "nothing has
    been saved".
    """
    try:
        session = new_session()
    except RuntimeError:
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    try:
        rows = translation_store.list_all(session)
    except SQLAlchemyError:
        logger.warning("Translation store read failed.", exc_info=True)
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    finally:
        session.close()
    return [_to_translation_response(row) for row in rows]


@app.delete("/translations/{translation_id}", status_code=204, response_model=None)
def delete_translation(translation_id: int) -> None:
    """Delete one saved translation by id.

    404 if no row with that id exists, 503 if the store is unavailable —
    mirrors ``save_translation``'s "no fallback, surface the failure"
    handling.
    """
    try:
        session = new_session()
    except RuntimeError:
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    try:
        deleted = translation_store.delete_translation(session, translation_id)
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Translation store delete failed.", exc_info=True)
        raise HTTPException(status_code=503, detail="Translation store unavailable")
    finally:
        session.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="Translation not found")


# ---------------------------------------------------------------------------
# Comprehension records (comprehension-response-ux): the 歷史紀錄 store, whose
# rows double as the work queue a worker drains. This resource replaces
# /translations and /comprehend; both are still served while the shipped client
# is cut over, and are removed -- along with a manual
# `DROP TABLE saved_translation` -- in the removal ticket.
# ---------------------------------------------------------------------------


_COMPREHENSION_STORE_UNAVAILABLE = "Comprehension store unavailable"


@contextmanager
def _comprehension_session():
    """Yield a session for one comprehension-store operation, or 503.

    Extracted because six routes need the identical open/rollback/close dance;
    ``/translations`` established the shape inline at three repeats, which does
    not survive doubling. Behaviour is unchanged from those routes: a store that
    was never initialised and one that fails mid-request both surface as 503,
    because these rows have no independent origin to fall back on -- reporting
    "unreachable" as "you have no history" would be a lie the reader cannot
    detect.

    Only ``SQLAlchemyError`` is converted; an ``HTTPException`` raised by the
    body (a 404, say) passes through untouched.
    """
    try:
        session = new_session()
    except RuntimeError:
        raise HTTPException(status_code=503, detail=_COMPREHENSION_STORE_UNAVAILABLE)
    try:
        yield session
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Comprehension store operation failed.", exc_info=True)
        raise HTTPException(status_code=503, detail=_COMPREHENSION_STORE_UNAVAILABLE)
    finally:
        session.close()


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


# Generous but bounded per-image ceiling on the base64 request payload,
# checked before any Claude call. Checking the base64 string length (rather
# than fully decoding to measure the actual image) is a fine, simpler proxy
# here -- this is a pure anomaly guard against a bug (e.g. a client sending an
# un-downscaled, full-resolution page) generating outsized cost, not a real
# validation of image content/dimensions. 8 MiB of base64 text (~6 MB
# decoded) is comfortably above a downscaled-to-~1024px page or a selection
# crop -- both are typically well under 1 MB as JPEG per the spec's
# Implementation Decisions -- while still catching a clearly wrong-sized
# payload before it reaches Claude.
_MAX_IMAGE_BASE64_CHARS = 8 * 1024 * 1024


def _guard_image_size(crop_base64: str, page_base64: str) -> None:
    """Reject an oversized crop/page image before any Claude call (413)."""
    if (
        len(crop_base64) > _MAX_IMAGE_BASE64_CHARS
        or len(page_base64) > _MAX_IMAGE_BASE64_CHARS
    ):
        raise HTTPException(status_code=413, detail="Image payload too large")


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


@app.post(
    "/comprehend",
    response_model=ComprehendResponse,
    response_model_exclude_none=True,  # a declined body is exactly {"status": "declined"}
)
def comprehend(body: ComprehendRequest) -> ComprehendResponse:
    """Translate + explain one selection via Claude (see comprehension_client).

    Two anomaly guards run first, before any DB/Claude call for the size
    check and before any Claude call for the cap check (see
    ``_guard_image_size``/``_reserve_daily_cap``): an oversized crop/page image
    is rejected 413, and the global daily request cap is rejected 429. Both
    exist only to bound accidental cost (e.g. a retry loop or an oversized
    payload), not as real per-user usage-limiting.

    Two genuine-success-vs-declined outcomes share HTTP 200,
    discriminated by ``status`` (per the llm-comprehension spec's
    Implementation Decisions) so the client can pick the right fallback/banner
    without guessing from a status code:

    - ``{"status": "ok", translation, grammarNotes, contextNotes,
      toneRegister}`` on a successful tool-use result.
    - ``{"status": "declined"}`` when Claude's response has no valid tool-use
      result (see ``comprehension_client.comprehend``'s docstring on why this
      is not gated on a specific ``stop_reason`` value).

    Any other failure -- a connection/API error from the Anthropic SDK -- is a
    normal HTTP 4xx/5xx via ``HTTPException``, never this 200 shape. Request
    validation (missing/malformed fields) is handled by FastAPI/Pydantic
    before this function runs (422).
    """
    _guard_image_size(body.cropImageBase64, body.pageImageBase64)
    _reserve_daily_cap()
    try:
        result = comprehension_client.comprehend(
            crop_image_base64=body.cropImageBase64,
            page_image_base64=body.pageImageBase64,
            source_text=body.sourceText,
            target_language_code=body.targetLanguageCode,
            use_stronger_model=body.useStrongerModel,
        )
    except anthropic.APIStatusError as exc:
        # The Anthropic SDK guarantees a 4xx/5xx status here; forward it
        # rather than collapsing every failure to a single code, without
        # exposing the API key (never present in the SDK's own error body).
        logger.warning("Claude API returned an error status.", exc_info=True)
        raise HTTPException(
            status_code=exc.status_code, detail="Comprehension request failed"
        )
    except (anthropic.APIConnectionError, anthropic.AnthropicError):
        logger.warning("Claude API call failed.", exc_info=True)
        raise HTTPException(
            status_code=502, detail="Comprehension service unavailable"
        )

    if result is None:
        return ComprehendResponse(status="declined")
    return ComprehendResponse(
        status="ok",
        translation=result.translation,
        grammarNotes=result.grammar_notes,
        contextNotes=result.context_notes,
        toneRegister=result.tone_register,
    )


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
