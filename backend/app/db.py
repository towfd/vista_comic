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
from pathlib import Path
from typing import Iterator, Optional

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    Engine,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    create_engine,
)
from sqlalchemy.dialects.postgresql import ARRAY
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


class LearningCard(Base):
    """One line the reader collected on purpose, to be reviewed later.

    Not a revival of ``saved_translation``. That table stored whatever the app
    decided to keep; a row here exists only because the reader pressed add,
    having read the source text and the translation and judged them right.
    **That press is the quality gate** — the source text is trustworthy because
    they corrected the OCR before anything else happened, the translation is
    not, and a deck built automatically would use spaced repetition to reinforce
    the model's mistakes. See ``.scratch/vocabulary-review/prd.md``.

    ``normalized_key`` is derived from ``source_text`` by ``normalization``
    and, with ``target_language``, is the card's identity. **The comic is
    deliberately not part of it**: the same word met in another work is the same
    word, and splitting it would fragment the ``lookup_count`` that later stages
    read as a forgetting signal.

    ``translation`` is whatever the reader was looking at when they pressed add
    -- on-device if they added straight after translating, Claude's if they
    waited for an explanation first. Nothing upgrades it afterwards: the stored
    wording is the one they actually read and approved.

    ``comic_id``/``chapter_id``/``page_number`` record the *first* encounter and
    are what the app's jump-to-source needs. No crop rectangle and no image, for
    the reason ``ComprehensionRecord`` gives: the page is re-derivable from the
    ids, and the reader's own framing is not worth a column.

    ``ladder_stage`` and ``due_on`` are written here and given meaning in stage
    3, where scheduling exists. Nothing in stage 1 reads them; they are present
    now so the reviewing stages inherit a populated column instead of a
    backfill.

    ``kind`` is the reader's own answer to "is this a word or a sentence",
    given by which of the two save buttons they pressed. **Not inferred**: which
    one a framed line is takes a tokeniser and some syntax to guess at, badly
    for Japanese especially, and the reader knows instantly. It decides which
    questions stage 3 asks and whether stage 4 generates a practice sentence
    for the card or treats the card as one.

    **Nullable, and deliberately so.** Cards collected before the column existed
    have no answer, and backfilling one would mean guessing — precisely what the
    two buttons exist to abolish. It is **not** part of the card's identity
    either: splitting on it would fragment ``lookup_count`` and put two visually
    identical rows in the library.

    ``lookup_count`` counts only the positive evidence -- the reader selecting a
    line they had already collected, which proves they had forgotten it.
    **Never the negative**: not looking a word up again is not evidence of
    knowing it, since the reader may simply not have reached that page.
    """

    __tablename__ = "learning_card"
    __table_args__ = (
        UniqueConstraint(
            "normalized_key", "target_language", name="uq_learning_card_identity"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source_text: Mapped[str] = mapped_column(String, nullable=False)
    normalized_key: Mapped[str] = mapped_column(String, nullable=False)
    translation: Mapped[str] = mapped_column(String, nullable=False)
    target_language: Mapped[str] = mapped_column(String, nullable=False)
    comic_id: Mapped[str] = mapped_column(String, nullable=False)
    chapter_id: Mapped[str] = mapped_column(String, nullable=False)
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    # Always NULL in stage 1. Set from stage 4, when a card can be picked out of
    # an explanation's breakdown. ``SET NULL`` rather than cascade: deleting a
    # history row must never delete something the reader deliberately kept.
    comprehension_record_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("comprehension_record.id", ondelete="SET NULL"),
        nullable=True,
    )
    kind: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    #: Where the card is in the scheduling model -- see ``scheduler.CardState``.
    #:
    #: **Stored, not derived**, which reverses the three-step day's design and is
    #: forced by two facts: a learning card's position is *which step, due at
    #: what minute*, which the review log has never carried; and stage 6's
    #: migration resets every card while keeping every review row, so "has
    #: answers" stopped meaning "has been met".
    state: Mapped[str] = mapped_column(String, nullable=False)
    #: Index into the reader's learning steps. NULL outside the learning states.
    learning_step: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    #: Which slot of ``ladder.LADDER_INTERVALS`` (0-6 since 2026-08-31).
    #:
    #: The column kept its name through stage 6 and changed meaning: it was the
    #: rung of a ladder that a wrong answer knocked to the bottom, and is now
    #: simply which interval the card has earned.
    ladder_stage: Mapped[int] = mapped_column(Integer, nullable=False)
    #: The slot to return to on graduating out of relearning; NULL when the card
    #: has never lapsed or has already used it. This is what makes a lapse cost
    #: one slot rather than everything.
    previous_stage: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    #: The **reader's** day on which this card stopped being new, or NULL if it
    #: still is. What the daily new-card quota counts.
    #:
    #: Stored rather than derived from the review log, for the same reason
    #: ``state`` is: the stage 6 migration resets cards while keeping their
    #: rows, so a card's oldest answer is not when it was met. A card reset
    #: today and met again today would otherwise be introduced for free.
    introduced_on: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    #: When the card next comes up. **A timestamp, not a date** (it was
    #: ``due_on`` until stage 6): learning steps are minutes apart, and a card
    #: due at 20:07 cannot be expressed as a day.
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    lookup_count: Mapped[int] = mapped_column(Integer, nullable=False)
    last_looked_up_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    archived_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class CardReview(Base):
    """One answer, exactly as it happened.

    The unit everything in the reviewing stages is computed from. A card's
    position in the three-step day is derived by replaying **today's** rows in
    order rather than stored, which is what makes a gap in practice cost
    nothing: there is no settlement moment, so nothing runs late, nothing runs
    three times, and a day the reader skipped is simply a day with no rows in
    it.

    ``elapsed_ms`` is written and read by nothing. The PRD keeps the log
    complete so that swapping the fixed ladder for FSRS later is an algorithm
    change rather than a data migration, and response time is the signal FSRS
    wants. Collecting it costs a column; collecting it **retroactively** is
    impossible -- the same reasoning that put ``lookup_count`` in from the first
    release.

    ``client_token`` exists so a resubmitted answer cannot count twice. A tapped
    button on a slow connection is exactly how one answer becomes two, and a
    duplicated wrong answer would drop a rung the reader never lost.

    Rows are deleted with their card: they describe a card, and once it is gone
    they describe nothing.
    """

    __tablename__ = "card_review"
    __table_args__ = (
        UniqueConstraint("client_token", name="uq_card_review_client_token"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    card_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("learning_card.id", ondelete="CASCADE"), nullable=False
    )
    question_type: Mapped[str] = mapped_column(String, nullable=False)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    elapsed_ms: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    client_token: Mapped[str] = mapped_column(String, nullable=False)
    #: Which of the **reader's** days this answer belonged to, sent by the app.
    #:
    #: Kept alongside ``reviewed_at`` rather than derived from it, because they
    #: answer different questions and the difference is not cosmetic:
    #: ``reviewed_at`` is the server clock, and grouping a UTC+8 reader's day by
    #: it would put everything before 08:00 on the previous day. The three-step
    #: day is grouped by this column.
    local_date: Mapped[date] = mapped_column(Date, nullable=False)
    #: Which mode asked the question: ``review`` (the schedule) or ``training``
    #: (永無止盡的訓練, which records everything and schedules nothing).
    #:
    #: A column on the row rather than a token prefix or a join to a session
    #: table. A review row is meant to be legible on its own; encoding the mode
    #: into ``client_token`` would overload an idempotency key with meaning and
    #: force ``LIKE`` queries, and a session table would need a lifecycle that a
    #: mode with no end cannot have.
    context: Mapped[str] = mapped_column(String, nullable=False)
    #: When the reader actually answered, **as reported by the app**.
    #:
    #: Separate from ``reviewed_at`` because offline practice makes them differ
    #: by hours, and scheduling from the moment an answer arrived would put a
    #: five-minute step in the wrong afternoon.
    answered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    #: When the answer reached the server. Orders a replay, and is the timestamp
    #: FSRS would want later.
    reviewed_at: Mapped[datetime] = mapped_column(
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


class StudySettings(Base):
    """The reader's scheduling settings. Exactly one row.

    On the backend rather than on the device because the backend recomputes
    schedules when an offline session flushes, and two copies that disagreed
    would produce two different ``due_at`` values for the same answer.

    One row, pinned by a check constraint, in the spirit of ``ComprehendUsage``'s
    natural key: this deployment has no per-user identity (ADR-0005), so there is
    nothing to key settings on.
    """

    __tablename__ = "study_settings"
    __table_args__ = (
        CheckConstraint("id = 1", name="ck_study_settings_single_row"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    #: Minutes between learning steps, in order. A list rather than three
    #: columns because "how many steps" and "how long each step is" are the same
    #: question, and writing three down assumes an answer to the first.
    learning_steps: Mapped[list[int]] = mapped_column(ARRAY(Integer), nullable=False)
    new_cards_per_day: Mapped[int] = mapped_column(Integer, nullable=False)


# Module-level engine/session factory, installed by ``init_engine`` at startup
# (or by the test harness against a throwaway database).
_engine: Optional[Engine] = None
_SessionLocal: Optional[sessionmaker[Session]] = None


def init_engine(database_url: Optional[str] = None) -> Engine:
    """Create the engine + session factory. Does **not** touch the schema.

    Idempotent enough for our needs: calling it again swaps in a fresh engine
    (used by tests to point at a throwaway database).

    It used to call ``Base.metadata.create_all`` here. Alembic owns the schema
    now, and leaving ``create_all`` in place would mean two mechanisms building
    it -- one of them silently creating tables the other believes do not exist
    yet, with nothing to notice the drift. See ``upgrade_schema`` below.

    Creates no connection: SQLAlchemy engines connect lazily, so an unreachable
    database surfaces at the first real query rather than here.
    """
    global _engine, _SessionLocal
    url = database_url or get_database_url()
    _engine = create_engine(url, pool_pre_ping=True, future=True)
    _SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False, future=True)
    return _engine


def upgrade_schema(database_url: Optional[str] = None) -> None:
    """Bring the database up to the latest migration (``alembic upgrade head``).

    Run in-process rather than from a shell entrypoint, because the caller has
    to tell two failures apart and a shell script cannot: a database that is
    simply unreachable is an outage the app degrades through, while a migration
    that will not apply means the schema is not what the code expects and the
    app must not serve. Both look like a non-zero exit from the command line;
    here, the first is an ``OperationalError`` and the second is anything else.

    Imported lazily so the Alembic dependency is only needed by the paths that
    actually migrate -- the app at startup and the test fixtures.
    """
    from alembic import command
    from alembic.config import Config

    config = Config(str(Path(__file__).resolve().parent.parent / "alembic.ini"))
    if database_url is not None:
        config.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(config, "head")


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
