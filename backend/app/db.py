"""Reading-progress persistence: engine, session, and the ``progress`` table.

Slice 4 introduces PostgreSQL for a single ``progress`` table only; the catalog
stays scan-derived (see ``docs/backend-architecture.md`` -> "Slice 4 storage
detail"). Access is **SQLAlchemy 2.0 + psycopg (sync)** to match the sync
FastAPI handlers. The table is created with ``CREATE TABLE IF NOT EXISTS`` via
``metadata.create_all`` at startup -- no Alembic for one table.

The engine and session factory are created once at startup (or, in tests, by a
fixture that points at a throwaway database). ``get_session`` is a FastAPI
dependency yielding a short-lived session per request.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Iterator, Optional

from sqlalchemy import Boolean, Date, Engine, Integer, String, create_engine
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    sessionmaker,
)
from sqlalchemy.types import DateTime

from .config import get_database_url


class Base(DeclarativeBase):
    """Declarative base for the reading-progress schema."""


class Progress(Base):
    """One saved reading position, keyed on the stable path-hash IDs.

    Primary key ``(comic_id, chapter_id)`` matches the catalog's server-generated
    IDs, so a rescan/restart preserves the join between catalog and progress.
    """

    __tablename__ = "progress"

    comic_id: Mapped[str] = mapped_column(String, primary_key=True)
    chapter_id: Mapped[str] = mapped_column(String, primary_key=True)
    last_page: Mapped[int] = mapped_column(Integer, nullable=False)
    page_count: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ComprehensionRecord(Base):
    """One auto-created comprehension record; the row is also the work queue.

    Replaced ``saved_translation`` (``comprehension-response-ux``): every
    translate now creates a row automatically rather than the reader choosing to
    save one, so this is a history of what was read, not a curated vocabulary
    book. The old table was dropped by hand in the removal ticket -- this project
    has no Alembic (see ``init_engine``), so ``create_all`` added this table for
    free but would never have altered the old one. See
    ``docs/manual-migrations.md``.

    ``status`` is the single discriminator for the row's whole lifecycle and
    doubles as the queue state a worker claims on:

    - ``pending``  -- enqueued, not yet claimed
    - ``running``  -- claimed by the worker
    - ``ok``       -- Claude returned an explanation
    - ``declined`` -- Claude declined to explain this selection
    - ``failed``   -- network/server/API error

    The old "all three note columns are NULL means translation-only" convention
    is deliberately gone: it cannot distinguish "still being produced" from
    "failed", which is the whole reason this table exists.

    ``translated_text`` is the on-device translation, written at enqueue and
    never modified afterwards; ``cloud_translation`` is Claude's own, filled only
    on ``ok``. Both are kept so display precedence stays a UI choice.

    ``usage_date`` records which UTC day this row's daily-cap reservation was
    drawn from, so a refund goes back to *that* day rather than to "today" -- a
    row enqueued at 23:59 and resolved at 00:00 would otherwise hand the new day
    a free request (see ``comprehend_usage_store``).

    No image column, by design: the page is always re-derivable from
    ``comic_id``/``chapter_id``/``page_number`` via the library on disk.
    """

    __tablename__ = "comprehension_record"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source_text: Mapped[str] = mapped_column(String, nullable=False)
    translated_text: Mapped[str] = mapped_column(String, nullable=False)
    cloud_translation: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    grammar_notes: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    context_notes: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    tone_register: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    target_language: Mapped[str] = mapped_column(String, nullable=False)
    comic_id: Mapped[str] = mapped_column(String, nullable=False)
    chapter_id: Mapped[str] = mapped_column(String, nullable=False)
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False)
    use_stronger_model: Mapped[bool] = mapped_column(Boolean, nullable=False)
    usage_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ComprehendUsage(Base):
    """Global daily request counter backing the Claude-spend cost guard.

    Not per-user -- this backend has no per-user identity (a single shared
    Cloudflare Access Service Token gates every request, see ADR-0005), so the
    cap is one counter for the whole deployment, keyed on calendar date.
    ``usage_date`` is the primary key (one row per day, like ``Progress``'s
    natural-key upsert), which is also how the cap resets automatically: a new
    date simply has no row yet, so no manual reset job is needed. Purely an
    anomaly guard against runaway cost (e.g. a retry-loop bug), not real
    usage-limiting -- see ``comprehend_usage_store.py``.
    """

    __tablename__ = "comprehend_usage"

    usage_date: Mapped[date] = mapped_column(Date, primary_key=True)
    request_count: Mapped[int] = mapped_column(Integer, nullable=False)


# Module-level engine/session factory, installed by ``init_engine`` at startup
# (or by the test harness against a throwaway database).
_engine: Optional[Engine] = None
_SessionLocal: Optional[sessionmaker[Session]] = None


def init_engine(database_url: Optional[str] = None) -> Engine:
    """Create the engine + session factory and ensure the table exists.

    Idempotent enough for our needs: calling it again swaps in a fresh engine
    (used by tests to point at a throwaway database). ``create_all`` issues
    ``CREATE TABLE IF NOT EXISTS`` so an existing table is left untouched.
    """
    global _engine, _SessionLocal
    url = database_url or get_database_url()
    _engine = create_engine(url, pool_pre_ping=True, future=True)
    _SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False, future=True)
    Base.metadata.create_all(_engine)
    return _engine


def get_engine() -> Engine:
    if _engine is None:
        raise RuntimeError("Database engine not initialized; call init_engine() first.")
    return _engine


def new_session() -> Session:
    """Return a standalone session (caller must close). Handy for tests/scripts."""
    if _SessionLocal is None:
        raise RuntimeError("Database engine not initialized; call init_engine() first.")
    return _SessionLocal()


def get_session() -> Iterator[Session]:
    """FastAPI dependency: yield a request-scoped session, always closed."""
    if _SessionLocal is None:
        raise RuntimeError("Database engine not initialized; call init_engine() first.")
    session = _SessionLocal()
    try:
        yield session
    finally:
        session.close()
