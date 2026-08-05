"""Global daily request-count guard for ``POST /comprehend`` (ticket 12).

Thin functions over a SQLAlchemy ``Session``, mirroring ``progress_store.py``'s
plain-function-over-a-session shape. Unlike ``progress_store``/
``translation_store`` (which model durable domain state), this module backs a
single anomaly guard: a global (not per-user -- see ``db.ComprehendUsage``'s
docstring and ADR-0005) count of ``/comprehend`` attempts for the current
calendar day, capped at ``DAILY_CAP``. It exists only to stop a bug (e.g. a
retry loop) from generating unbounded Claude spend -- it is not real
usage-limiting, so it does not need to be exact under heavy concurrency,
only atomic enough that a burst of requests can't blow past the cap by much.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from .db import ComprehendUsage

# Purely an anomaly guard (per the spec's Implementation Decisions), not real
# usage-limiting -- 300/day comfortably covers real manual use while still
# catching a runaway bug. A module-level attribute (not a function default
# parameter) so tests can monkeypatch it and have the override actually take
# effect at call time (see comprehend_usage_store.check_and_increment's `cap`
# callers in main.py, which read this attribute dynamically rather than
# capturing it at import time).
DAILY_CAP = 300


def _today_utc() -> date:
    # UTC, not local server time, so the cap resets at a consistent moment
    # regardless of the host's timezone -- matches this codebase's existing
    # UTC convention for stored timestamps (see progress_store.iso_utc).
    return datetime.now(timezone.utc).date()


def check_and_increment(
    session: Session,
    *,
    cap: int = DAILY_CAP,
    today: Optional[date] = None,
) -> bool:
    """Atomically increment today's count and report whether it was allowed.

    Returns ``True`` (and increments) when today's count was below ``cap``
    before this call; returns ``False`` (and leaves the stored count
    unchanged) once the cap has already been reached, so a request that keeps
    getting rejected does not keep bumping the counter forever.

    Single ``INSERT ... ON CONFLICT (usage_date) DO UPDATE ... WHERE
    request_count < cap RETURNING`` statement (mirrors
    ``progress_store.upsert``'s atomic upsert-and-return shape): the first
    request for a new date inserts the row at 1 and is allowed; a later
    request on the same date only applies the conflict update -- incrementing
    -- when the existing count is still under ``cap``. When the WHERE
    condition is false (already at/over cap) Postgres treats the conflicting
    row as a no-op, so RETURNING yields no row and the stored count is left
    exactly at ``cap`` rather than climbing further. This one statement is
    atomic against concurrent callers (Postgres row-level locking), which is
    all the precision this anomaly guard needs.

    ``today`` is injectable so tests can exercise "yesterday's" and "today's"
    counts independently without waiting for a real calendar day to roll over
    (proving the natural-reset behavior); it defaults to the current UTC date.
    """
    usage_date = today if today is not None else _today_utc()
    stmt = (
        pg_insert(ComprehendUsage)
        .values(usage_date=usage_date, request_count=1)
        .on_conflict_do_update(
            index_elements=["usage_date"],
            set_={"request_count": ComprehendUsage.request_count + 1},
            where=(ComprehendUsage.request_count < cap),
        )
        .returning(ComprehendUsage.request_count)
    )
    result = session.execute(stmt).first()
    session.commit()
    return result is not None


def get_count(session: Session, *, today: Optional[date] = None) -> int:
    """Return today's stored count, or 0 if no row exists yet (test/debug helper)."""
    usage_date = today if today is not None else _today_utc()
    row = session.get(ComprehendUsage, usage_date)
    return row.request_count if row is not None else 0
