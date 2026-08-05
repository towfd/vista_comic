"""Repository for comprehension records (the 歷史紀錄 store).

Thin functions over a SQLAlchemy ``Session``, mirroring ``progress_store.py``/
``translation_store.py``'s plain-function-over-a-session shape (no repository
class).

Like ``translation_store`` and unlike ``progress_store``, there are no ``safe_*``
degrade-to-default read wrappers: the catalog reads degrade gracefully because
the library folder is an independent source of truth, but these rows *are* the
data, so a store failure surfaces to the caller (503 in ``main.py``) rather than
silently returning an empty list. Reporting "the store is unreachable" as "you
have no history" would be a lie the reader cannot detect.

Claiming rows for execution is deliberately absent -- that belongs to the worker
ticket, not to this API surface.
"""

from __future__ import annotations

from datetime import date
from typing import List, Optional

from sqlalchemy import delete, func, insert, select, update
from sqlalchemy.orm import Session

from .db import ComprehensionRecord

# The row's whole lifecycle, and the queue state a worker claims on. One column,
# five values -- see ``db.ComprehensionRecord``.
STATUS_PENDING = "pending"
STATUS_RUNNING = "running"
STATUS_OK = "ok"
STATUS_DECLINED = "declined"
STATUS_FAILED = "failed"


def insert_record(
    session: Session,
    *,
    source_text: str,
    translated_text: str,
    target_language: str,
    comic_id: str,
    chapter_id: str,
    page_number: int,
    use_stronger_model: bool,
    usage_date: date,
) -> ComprehensionRecord:
    """Insert one ``pending`` record; return it with the DB-generated columns.

    ``created_at`` uses the database clock (``now()``) as the source of truth,
    matching ``progress_store.upsert``'s and ``translation_store``'s convention.
    Returns a plain (session-detached) row built from the caller's values plus
    the generated ones, so the endpoint can echo the record without a second
    round trip.

    ``usage_date`` is passed in rather than derived here: it must be the date
    the caller's own cap reservation was taken against (see
    ``comprehend_usage_store.refund``).
    """
    stmt = (
        insert(ComprehensionRecord)
        .values(
            source_text=source_text,
            translated_text=translated_text,
            cloud_translation=None,
            grammar_notes=None,
            context_notes=None,
            tone_register=None,
            target_language=target_language,
            comic_id=comic_id,
            chapter_id=chapter_id,
            page_number=page_number,
            status=STATUS_PENDING,
            is_read=False,
            use_stronger_model=use_stronger_model,
            usage_date=usage_date,
            created_at=func.now(),
        )
        .returning(ComprehensionRecord.id, ComprehensionRecord.created_at)
    )
    generated = session.execute(stmt).one()
    session.commit()
    return ComprehensionRecord(
        id=generated.id,
        source_text=source_text,
        translated_text=translated_text,
        cloud_translation=None,
        grammar_notes=None,
        context_notes=None,
        tone_register=None,
        target_language=target_language,
        comic_id=comic_id,
        chapter_id=chapter_id,
        page_number=page_number,
        status=STATUS_PENDING,
        is_read=False,
        use_stronger_model=use_stronger_model,
        usage_date=usage_date,
        created_at=generated.created_at,
    )


def list_all(session: Session) -> List[ComprehensionRecord]:
    """Every record, newest first."""
    rows = session.execute(
        select(ComprehensionRecord).order_by(ComprehensionRecord.created_at.desc())
    ).scalars()
    return list(rows)


def get(session: Session, record_id: int) -> Optional[ComprehensionRecord]:
    """One record by id, or ``None`` -- the result screen's poll target."""
    return session.get(ComprehensionRecord, record_id)


def set_read(session: Session, record_id: int, *, is_read: bool) -> bool:
    """Set one record's read flag; report whether a row existed.

    One function for both directions -- the two only ever differed by the value
    written. Deliberately idempotent: marking an already-read record read again
    succeeds rather than erroring, because the caller is a screen reacting to
    being opened and has no useful way to handle "that was already read".
    """
    result = session.execute(
        update(ComprehensionRecord)
        .where(ComprehensionRecord.id == record_id)
        .values(is_read=is_read)
    )
    session.commit()
    return result.rowcount > 0


def requeue_failed(
    session: Session, record_id: int, *, usage_date: date
) -> Optional[ComprehensionRecord]:
    """Return a ``failed`` record to ``pending`` for another attempt.

    Guarded on ``status == failed`` inside the UPDATE rather than by a separate
    read-then-write, so a concurrent claim cannot slip between the check and the
    change. Returns the updated row, or ``None`` when nothing matched -- which
    covers both "no such record" and "that record is not failed"; the endpoint
    distinguishes those with a follow-up existence check.

    Takes a fresh ``usage_date`` because retrying costs another request against
    the daily cap, reserved by the caller before this runs.
    """
    result = session.execute(
        update(ComprehensionRecord)
        .where(
            ComprehensionRecord.id == record_id,
            ComprehensionRecord.status == STATUS_FAILED,
        )
        .values(
            status=STATUS_PENDING,
            usage_date=usage_date,
            cloud_translation=None,
            grammar_notes=None,
            context_notes=None,
            tone_register=None,
            is_read=False,
        )
        .returning(ComprehensionRecord.id)
    )
    updated = result.first()
    session.commit()
    if updated is None:
        return None
    return session.get(ComprehensionRecord, record_id)


def delete_record(session: Session, record_id: int) -> Optional[ComprehensionRecord]:
    """Delete one record, returning what was deleted (or ``None``).

    Returns the deleted row rather than a bool because the caller needs its
    ``status`` and ``usage_date`` to decide whether a cap reservation has to be
    refunded -- a still-pending row never reached Claude, so its request is
    given back.

    The row is detached with ``expunge`` before the delete so the caller can
    still read it afterwards; rebuilding it field by field would mean every new
    column had to be added here too.
    """
    row = session.get(ComprehensionRecord, record_id)
    if row is None:
        return None
    session.expunge(row)
    session.execute(
        delete(ComprehensionRecord).where(ComprehensionRecord.id == record_id)
    )
    session.commit()
    return row
