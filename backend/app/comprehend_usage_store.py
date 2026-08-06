"""Global daily request-count guard, reserved when a record is enqueued.

Thin functions over a SQLAlchemy ``Session``, mirroring ``progress_store.py``'s
plain-function-over-a-session shape. Unlike ``progress_store``/
``comprehension_store`` (which model durable domain state), this module backs a
single anomaly guard: a global (not per-user -- see ``db.ComprehendUsage``'s
docstring and ADR-0005) count of Claude requests reserved for the current
calendar day, capped at ``DAILY_CAP``. The reservation is taken at
``POST /comprehensions`` and given back only when the request never reached
Claude, so the queue can never grow longer than the remaining budget. It exists only to stop a bug (e.g. a
retry loop) from generating unbounded Claude spend -- it is not real
usage-limiting, so it does not need to be exact under heavy concurrency,
only atomic enough that a burst of requests can't blow past the cap by much.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import update
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

# What one capped request can cost, recorded here beside the cap because the two
# only mean something together: the cap bounds the *number* of requests, and the
# tier bounds what each one costs. Under `comprehension-response-ux` the tier is
# a reader-facing picker (the per-device "deeper explanation" toggle), so the
# whole feature's cost profile moves with a setting no deploy touches.
#
# Checked against Anthropic's published per-token pricing on 2026-08-06, for the
# two models `comprehension_client` actually selects between:
#
#   claude-haiku-4-5-20251001  $1 / MTok in,  $5 / MTok out   (default tier)
#   claude-sonnet-5            $3 / MTok in, $15 / MTok out   (stronger tier)
#
# So the stronger tier costs **3x** the default, on input and output alike.
# Sonnet 5 is under introductory pricing ($2/$10) until 2026-08-31, making the
# ratio 2x until then; 3x is the number to plan against, since it is what the
# ratio returns to. Re-check when either model is changed.
#
# Recorded as prose rather than a constant on purpose: nothing computes against
# it, and a second copy of the number in code is a copy that can drift from the
# comment explaining it.


def today_utc() -> date:
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
    usage_date = today if today is not None else today_utc()
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


def refund(session: Session, *, usage_date: date) -> None:
    """Give one reserved request back to ``usage_date``'s count.

    The cap is *reserved* when work is enqueued, not when Claude is actually
    called, so that a full cap can be reported to the reader immediately and the
    queue can never grow longer than the remaining budget. This is the settle
    half: it runs only when the request will never reach Claude at all (the row
    was deleted while still pending, or the worker failed before issuing the
    call). Anything that reached Claude keeps its count -- including a declined
    result, which produced billable tokens.

    ``usage_date`` is required and comes from the row's own stored reservation
    date rather than defaulting to today. A row reserved at 23:59 and released
    at 00:00 must refund to the day it drew from; refunding to "today" would
    silently hand the new day an extra request.

    Never drops below zero: this is an anomaly guard, and a stray double-refund
    should not manufacture budget. Missing row is a no-op for the same reason.

    One atomic ``UPDATE ... WHERE request_count > 0``, matching
    ``check_and_increment``'s single-statement shape rather than a
    read-then-write: a refund racing an enqueue on the same date would otherwise
    lose one of the two updates, and this counter is the only thing standing
    between a bug and unbounded spend.
    """
    session.execute(
        update(ComprehendUsage)
        .where(
            ComprehendUsage.usage_date == usage_date,
            ComprehendUsage.request_count > 0,
        )
        .values(request_count=ComprehendUsage.request_count - 1)
    )
    session.commit()


def get_count(session: Session, *, today: Optional[date] = None) -> int:
    """Return today's stored count, or 0 if no row exists yet (test/debug helper)."""
    usage_date = today if today is not None else today_utc()
    row = session.get(ComprehendUsage, usage_date)
    return row.request_count if row is not None else 0
