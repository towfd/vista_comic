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

Also provides:
    GET  /healthz           -> liveness + catalog size
    POST /rescan            -> manual re-scan hook (optional per the doc)

Media is served read-only: every request re-resolves the joined filesystem path
and requires it to stay under the library root before streaming (see _safe_file).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

import anthropic
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.exc import SQLAlchemyError

from . import (
    comprehend_usage_store,
    comprehension_client,
    progress_store,
    translation_store,
)
from .config import get_library_root
from .db import SavedTranslation, init_engine, new_session
from .models import (
    ChapterDetail,
    ChapterSummary,
    ComicDetail,
    ComicSummary,
    ComprehendRequest,
    ComprehendResponse,
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


def _guard_daily_cap() -> None:
    """Reject once the global daily ``/comprehend`` request cap is reached (429).

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
    try:
        session = new_session()
    except RuntimeError:
        logger.warning(
            "Comprehension usage store not initialized; allowing the request "
            "without a daily-cap check."
        )
        return
    try:
        allowed = comprehend_usage_store.check_and_increment(
            session, cap=comprehend_usage_store.DAILY_CAP
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


@app.post(
    "/comprehend",
    response_model=ComprehendResponse,
    response_model_exclude_none=True,  # a declined body is exactly {"status": "declined"}
)
def comprehend(body: ComprehendRequest) -> ComprehendResponse:
    """Translate + explain one selection via Claude (see comprehension_client).

    Two anomaly guards run first, before any DB/Claude call for the size
    check and before any Claude call for the cap check (see
    ``_guard_image_size``/``_guard_daily_cap``): an oversized crop/page image
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
    _guard_daily_cap()
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
