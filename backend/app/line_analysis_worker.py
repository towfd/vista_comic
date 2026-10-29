"""Background worker that turns pending line analyses into results.

The same shape as ``comprehension_worker``, for the same reasons: a plain
daemon thread around ``process_pending``, which is synchronous and holds all of
the logic, so tests drive it directly with no threads or sleeps.

One rule differs. The comprehension worker keeps a reservation that reached
Claude; here **every failure gives its reservation back** -- an error, a
refusal, an unusable answer, a restart mid-call. The spec chose that so a
failure never costs the reader part of the day's allowance; the cap is still
there to stop a runaway, and a failure needs a person to press 重試 again.
"""

from __future__ import annotations

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Callable, Optional

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from . import comprehend_usage_store, line_analysis_client, line_analysis_store
from .db import LineAnalysis, new_session
from .line_analysis_client import InvalidAnalysis, Name

logger = logging.getLogger("vista_comic.line_analysis")

# Bounds Claude spend, not threads; one reader rarely has more than a couple of
# lines waiting.
MAX_CONCURRENT_JOBS = 2

POLL_INTERVAL_SECONDS = 2.0


def _fail(session: Session, row: LineAnalysis, failure: str) -> None:
    logger.warning("Line analysis %s failed: %s", row.id, failure, exc_info=True)
    usage_date = line_analysis_store.fail(session, row.id, failure=failure)
    if usage_date is not None:
        comprehend_usage_store.refund(session, usage_date=usage_date)


def run_analysis(session: Session, row: LineAnalysis) -> None:
    """Run one claimed row to ``done`` or ``failed``."""
    try:
        result = line_analysis_client.analyse(
            model=row.model,
            source_text=row.source_text,
            translation=row.translation,
            names=[Name(source=n["source"], target=n["target"]) for n in row.names],
        )
    except InvalidAnalysis:
        _fail(session, row, line_analysis_store.FAILURE_INVALID)
        return
    except Exception:  # noqa: BLE001 -- an SDK error, a missing key: one row, not the queue
        _fail(session, row, line_analysis_store.FAILURE_ERROR)
        return

    if result is line_analysis_client.REFUSED:
        _fail(session, row, line_analysis_store.FAILURE_REFUSED)
        return
    if not line_analysis_client.is_usable(result, row.source_text):
        _fail(session, row, line_analysis_store.FAILURE_INVALID)
        return
    line_analysis_store.complete(session, row.id, result=result)


def process_pending(
    *,
    limit: int = MAX_CONCURRENT_JOBS,
    session_factory: Callable[[], Session] = new_session,
) -> int:
    """Claim up to ``limit`` pending rows, run them, and report how many ran."""
    try:
        claim_session = session_factory()
    except RuntimeError:
        return 0
    try:
        ids = line_analysis_store.claim_pending(claim_session, limit=limit)
    except SQLAlchemyError:
        claim_session.rollback()
        logger.warning("Could not claim line analyses.", exc_info=True)
        return 0
    finally:
        claim_session.close()

    if not ids:
        return 0

    def run_one(analysis_id: int) -> None:
        session = session_factory()
        try:
            row = line_analysis_store.get(session, analysis_id)
            if row is not None:
                run_analysis(session, row)
        except Exception:  # noqa: BLE001 -- a row that escapes stays `running` until restart
            session.rollback()
            logger.warning(
                "Line analysis %s: unexpected failure while running.",
                analysis_id,
                exc_info=True,
            )
        finally:
            session.close()

    with ThreadPoolExecutor(max_workers=limit) as pool:
        list(pool.map(run_one, ids))
    return len(ids)


def release_orphans(session_factory: Callable[[], Session] = new_session) -> int:
    """Fail every row a restart cut off, refunding each; report how many."""
    try:
        session = session_factory()
    except RuntimeError:
        return 0
    try:
        dates = line_analysis_store.fail_orphaned_claims(session)
        for usage_date in dates:
            comprehend_usage_store.refund(session, usage_date=usage_date)
        if dates:
            logger.info("Marked %s interrupted line analysis(es) failed.", len(dates))
        return len(dates)
    except SQLAlchemyError:
        session.rollback()
        logger.warning("Could not release orphaned line analyses.", exc_info=True)
        return 0
    finally:
        session.close()


class LineAnalysisWorker:
    """The daemon thread that keeps calling ``process_pending``."""

    def __init__(self, *, interval: float = POLL_INTERVAL_SECONDS) -> None:
        self._interval = interval
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        release_orphans()
        self._thread = threading.Thread(
            target=self._loop, name="line-analysis-worker", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                ran = process_pending()
            except Exception:  # noqa: BLE001 -- the loop must outlive any one failure
                logger.warning("Line analysis drain failed.", exc_info=True)
                ran = 0
            if ran == 0:
                self._stop.wait(self._interval)
