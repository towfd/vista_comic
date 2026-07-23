"""Repository for the reading-progress store.

Thin functions over a SQLAlchemy ``Session`` that encapsulate every SQL access
the endpoints need. Two read helpers are shaped to avoid N+1 queries:

- ``progress_by_chapter(session, comic_id)`` -- one query for a whole comic's
  chapters (drives per-chapter ``readState`` and the comic's ``lastReadAt``).
- ``last_read_at_by_comic(session)`` -- one grouped query for the library list
  (``GET /comics``), returning each comic's max ``updated_at``.

``readState`` / ``lastReadAt`` / ``lastReadPage`` are derived live from these
rows (see ``docs/backend-architecture.md`` -> "Field values by slice").
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Callable, Dict, Optional, TypeVar

from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from . import db
from .db import Progress

logger = logging.getLogger("vista_comic.progress")

_T = TypeVar("_T")


def iso_utc(dt: datetime) -> str:
    """Serialize a (tz-aware) timestamp as an ISO-8601 string in UTC."""
    return dt.astimezone(timezone.utc).isoformat()


def read_state(last_page: Optional[int], page_count: int) -> str:
    """Derive a chapter's read state.

    No stored progress -> ``unread``; ``last_page >= page_count`` -> ``read``;
    otherwise ``reading``. ``page_count`` is the catalog's authoritative count so
    a chapter that grew since the last read is handled correctly.
    """
    if last_page is None:
        return "unread"
    return "read" if last_page >= page_count else "reading"


def upsert(
    session: Session,
    comic_id: str,
    chapter_id: str,
    last_page: int,
    page_count: int,
) -> datetime:
    """Insert or update one progress row; return the DB-clock ``updated_at``.

    ``ON CONFLICT (comic_id, chapter_id)`` refreshes ``last_page``,
    ``page_count`` and ``updated_at`` so repeated saves keep exactly one row.
    ``updated_at`` uses the database clock (``now()``) as the source of truth.
    """
    stmt = (
        pg_insert(Progress)
        .values(
            comic_id=comic_id,
            chapter_id=chapter_id,
            last_page=last_page,
            page_count=page_count,
            updated_at=func.now(),
        )
        .on_conflict_do_update(
            index_elements=["comic_id", "chapter_id"],
            set_={
                "last_page": last_page,
                "page_count": page_count,
                "updated_at": func.now(),
            },
        )
        .returning(Progress.updated_at)
    )
    updated_at = session.execute(stmt).scalar_one()
    session.commit()
    return updated_at


def get(session: Session, comic_id: str, chapter_id: str) -> Optional[Progress]:
    """Return the stored row for one chapter, or ``None`` if there is none."""
    return session.get(Progress, (comic_id, chapter_id))


def progress_by_chapter(session: Session, comic_id: str) -> Dict[str, Progress]:
    """All progress rows for one comic, keyed by ``chapter_id`` (one query)."""
    rows = session.execute(
        select(Progress).where(Progress.comic_id == comic_id)
    ).scalars()
    return {row.chapter_id: row for row in rows}


def last_read_at_by_comic(session: Session) -> Dict[str, datetime]:
    """Max ``updated_at`` per comic across all its chapters (one grouped query)."""
    rows = session.execute(
        select(Progress.comic_id, func.max(Progress.updated_at)).group_by(
            Progress.comic_id
        )
    ).all()
    return {comic_id: max_updated for comic_id, max_updated in rows}


# --- resilient read wrappers -------------------------------------------------
#
# The catalog is scan-derived and independent of the progress store, so a DB
# outage must NOT break catalog browsing or the reader. These helpers open their
# own short-lived session and degrade to "no progress" (the given default) when
# the store is unreachable — whether the engine was never initialised (Postgres
# down at startup) or a query fails at request time (Postgres down mid-run).
# Writes have no such fallback: a failed write surfaces to the caller (503).


def _safe_read(fn: Callable[[Session], _T], default: _T) -> _T:
    try:
        session = db.new_session()
    except RuntimeError:
        # Engine never initialised (e.g. Postgres was down at startup).
        return default
    try:
        return fn(session)
    except SQLAlchemyError:
        logger.warning(
            "Progress store read failed; serving without progress.", exc_info=True
        )
        return default
    finally:
        session.close()


def safe_last_read_at_by_comic() -> Dict[str, datetime]:
    """``last_read_at_by_comic`` that returns ``{}`` if the store is unavailable."""
    return _safe_read(last_read_at_by_comic, {})


def safe_progress_by_chapter(comic_id: str) -> Dict[str, Progress]:
    """``progress_by_chapter`` that returns ``{}`` if the store is unavailable."""
    return _safe_read(lambda s: progress_by_chapter(s, comic_id), {})


def safe_get(comic_id: str, chapter_id: str) -> Optional[Progress]:
    """``get`` that returns ``None`` if the store is unavailable."""
    return _safe_read(lambda s: get(s, comic_id, chapter_id), None)
