"""Repository for line analyses: the stored results and the queue in one table.

Plain functions over a SQLAlchemy ``Session``, like ``comprehension_store``.
The top half is what the endpoint needs (find by identity, create, re-queue);
the bottom half is the worker's (claim, finish, fail, release orphans).

Every state change is a single guarded ``UPDATE``, never a read-then-write, so
a request and the worker racing on one row cannot both win.
"""

from __future__ import annotations

from datetime import date
from typing import Any, List, Optional

from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from .db import LineAnalysis

STATUS_PENDING = "pending"
STATUS_RUNNING = "running"
STATUS_DONE = "done"
STATUS_FAILED = "failed"

FAILURE_ERROR = "error"
FAILURE_REFUSED = "refused"
FAILURE_INVALID = "invalid"
FAILURE_INTERRUPTED = "interrupted"


def get(session: Session, analysis_id: int) -> Optional[LineAnalysis]:
    return session.get(LineAnalysis, analysis_id)


def find(
    session: Session, *, source_key: str, translation: str, model: str
) -> Optional[LineAnalysis]:
    """The analysis with this identity, or ``None``."""
    return session.execute(
        select(LineAnalysis).where(
            LineAnalysis.source_key == source_key,
            LineAnalysis.translation == translation,
            LineAnalysis.model == model,
        )
    ).scalar_one_or_none()


def create(
    session: Session,
    *,
    source_text: str,
    source_key: str,
    translation: str,
    model: str,
    names: list[dict[str, str]],
    usage_date: date,
) -> Optional[LineAnalysis]:
    """Insert a ``pending`` analysis; ``None`` if one with this identity appeared meanwhile.

    ``ON CONFLICT DO NOTHING`` rather than catching the unique violation, so a
    second request for the same line arriving in the same instant loses
    quietly and the caller can hand back the winner instead.
    """
    inserted = session.execute(
        pg_insert(LineAnalysis)
        .values(
            source_text=source_text,
            source_key=source_key,
            translation=translation,
            model=model,
            names=names,
            status=STATUS_PENDING,
            failure=None,
            result=None,
            usage_date=usage_date,
            created_at=func.now(),
            updated_at=func.now(),
        )
        .on_conflict_do_nothing(constraint="uq_line_analysis_identity")
        .returning(LineAnalysis.id)
    ).first()
    session.commit()
    return None if inserted is None else session.get(LineAnalysis, inserted.id)


def requeue(
    session: Session,
    analysis_id: int,
    *,
    source_text: str,
    names: list[dict[str, str]],
    usage_date: date,
) -> Optional[LineAnalysis]:
    """Send a ``done`` or ``failed`` analysis back to ``pending``; ``None`` if it was neither.

    The old result and failure are cleared: a refresh means the reader no longer
    wants them. The line's casing and the names are taken from this request, the
    latest the reader sent.
    """
    updated = session.execute(
        update(LineAnalysis)
        .where(
            LineAnalysis.id == analysis_id,
            LineAnalysis.status.in_([STATUS_DONE, STATUS_FAILED]),
        )
        .values(
            status=STATUS_PENDING,
            failure=None,
            result=None,
            source_text=source_text,
            names=names,
            usage_date=usage_date,
            updated_at=func.now(),
        )
        .returning(LineAnalysis.id)
    ).first()
    session.commit()
    if updated is None:
        return None
    # The row may already be in the session's identity map from an earlier read.
    row = session.get(LineAnalysis, analysis_id)
    session.refresh(row)
    return row


# ---------------------------------------------------------------------------
# Queue side.
# ---------------------------------------------------------------------------


def claim_pending(session: Session, *, limit: int) -> List[int]:
    """Claim up to ``limit`` oldest pending rows; return their ids (see ``comprehension_store``)."""
    claimable = (
        select(LineAnalysis.id)
        .where(LineAnalysis.status == STATUS_PENDING)
        .order_by(LineAnalysis.updated_at)
        .limit(limit)
        .with_for_update(skip_locked=True)
        .scalar_subquery()
    )
    result = session.execute(
        update(LineAnalysis)
        .where(LineAnalysis.id.in_(claimable))
        .values(status=STATUS_RUNNING)
        .returning(LineAnalysis.id)
    )
    ids = [row.id for row in result]
    session.commit()
    return ids


def complete(session: Session, analysis_id: int, *, result: dict[str, Any]) -> None:
    """Store a usable answer and mark the row ``done``."""
    session.execute(
        update(LineAnalysis)
        .where(LineAnalysis.id == analysis_id, LineAnalysis.status == STATUS_RUNNING)
        .values(status=STATUS_DONE, result=result, failure=None, updated_at=func.now())
    )
    session.commit()


def fail(session: Session, analysis_id: int, *, failure: str) -> Optional[date]:
    """Mark a running row ``failed`` with its reason; return its reservation date.

    ``None`` when the row was not running any more, so the caller refunds only
    a reservation this call actually ended.
    """
    failed = session.execute(
        update(LineAnalysis)
        .where(LineAnalysis.id == analysis_id, LineAnalysis.status == STATUS_RUNNING)
        .values(status=STATUS_FAILED, failure=failure, updated_at=func.now())
        .returning(LineAnalysis.usage_date)
    ).first()
    session.commit()
    return None if failed is None else failed.usage_date


def fail_orphaned_claims(session: Session) -> List[date]:
    """Mark every ``running`` row ``failed``/``interrupted``; return their reservation dates.

    Run once at startup, when nothing in this process can be running yet (one
    uvicorn worker), so every ``running`` row was cut off by a restart. Unlike
    the comprehension queue these are not re-run: the reader may have long
    stopped waiting, and a re-run is one press of 重試 away. The dates come back
    so the caller can refund each one.
    """
    result = session.execute(
        update(LineAnalysis)
        .where(LineAnalysis.status == STATUS_RUNNING)
        .values(
            status=STATUS_FAILED, failure=FAILURE_INTERRUPTED, updated_at=func.now()
        )
        .returning(LineAnalysis.usage_date)
    )
    dates = [row.usage_date for row in result]
    session.commit()
    return dates
