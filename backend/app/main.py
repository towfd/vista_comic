"""FastAPI application: scan the manga library on startup and serve the catalog.

Slice 1 endpoints (see docs/backend-architecture.md):
    GET  /comics            -> [ { id, title, coverUrl, chapterCount, lastReadAt } ]
    GET  /comics/{comicId}  -> { id, title, coverUrl, chapters: [ ... ] }

Also provides:
    GET  /healthz           -> liveness + catalog size
    POST /rescan            -> manual re-scan hook (optional per the doc)

Not in this slice: /media and the per-chapter pages endpoint (Slice 2).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException

from .config import get_library_root
from .models import ChapterSummary, ComicDetail, ComicSummary
from .scanner import Catalog, ComicEntry, scan_library

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


def _cover_url(comic_id: str) -> str:
    """Consistent media-path shape using the opaque comic ID.

    v1 does not serve images; Slice 2 implements this route. The shape uses the
    stable ID (not a raw folder name) to avoid path-encoding / traversal.
    """
    return f"/media/{comic_id}/cover"


def _to_summary(comic: ComicEntry) -> ComicSummary:
    return ComicSummary(
        id=comic.id,
        title=comic.title,
        coverUrl=_cover_url(comic.id),
        chapterCount=comic.chapter_count,
        lastReadAt=None,
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
def list_comics() -> list[ComicSummary]:
    catalog = _require_catalog()
    return [_to_summary(c) for c in catalog.comics]


@app.get("/comics/{comic_id}", response_model=ComicDetail)
def get_comic(comic_id: str) -> ComicDetail:
    catalog = _require_catalog()
    comic = catalog.by_id.get(comic_id)
    if comic is None:
        raise HTTPException(status_code=404, detail="Comic not found")
    return ComicDetail(
        id=comic.id,
        title=comic.title,
        coverUrl=_cover_url(comic.id),
        chapters=[
            ChapterSummary(
                id=ch.id,
                number=ch.number,
                title=ch.title,
                pageCount=ch.page_count,
                readState="unread",
            )
            for ch in comic.chapters
        ],
    )


@app.post("/rescan")
def rescan() -> dict:
    """Manually rebuild the in-memory catalog from the folder (read-only)."""
    catalog = _rescan()
    return {
        "status": "rescanned",
        "comics": len(catalog.comics),
        "chapters": sum(c.chapter_count for c in catalog.comics),
    }
