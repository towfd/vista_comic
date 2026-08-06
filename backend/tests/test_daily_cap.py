"""Tests for the daily-request cap, the one cost guard that survives.

The cap moved from ``POST /comprehend`` to ``POST /comprehensions``
(``comprehension-response-ux``): it is now *reserved at enqueue*, so an
exhausted budget is refused at the moment the reader acts and the queue can
never grow longer than the remaining budget. The endpoint-level "reserve,
refuse, refund" behaviour is covered where the rest of the resource is, in
``test_comprehension_records.py``; what lives here is the store underneath it
and the two ways the store being unavailable is allowed to go.

The image-size ceiling that used to sit beside this guard is gone with the
endpoint it protected. No client uploads an image any more -- the worker reads
the page off the library and downscales it itself (see
``test_comprehension_worker.py``), so there is no request payload left to
bound.

The DB-backed tests need a real throwaway Postgres and, where it is
unreachable, error the same way the rest of this suite's DB-backed tests do
(see ``conftest.py``'s module docstring) -- a known environment limitation, not
a new kind of failure. They inject a small effective cap rather than sending
300 real requests.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app import comprehend_usage_store, main

_ENQUEUE_BODY = {
    "sourceText": "Xin chào",
    "translatedText": "你好",
    "targetLanguage": "zh-Hant",
    "comicId": "comic-1",
    "chapterId": "chapter-1",
    "pageNumber": 3,
}


# --- the store underneath the guard ------------------------------------------


@pytest.fixture
def usage_db(_progress_engine):
    """Truncate the ``comprehend_usage`` table before each test that uses it.

    Mirrors ``conftest.py``'s ``progress_db``/``comprehension_db`` fixtures,
    reusing the shared ``_progress_engine`` session fixture (which already
    creates every table on ``Base``, including ``comprehend_usage``) without
    needing to touch ``conftest.py``.
    """
    with _progress_engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE comprehend_usage"))
    return _progress_engine


@pytest.fixture
def usage_session(usage_db):
    from app import db

    session = db.new_session()
    try:
        yield session
    finally:
        session.close()


def test_check_and_increment_allows_and_increments_under_cap(usage_session):
    allowed_first = comprehend_usage_store.check_and_increment(usage_session, cap=2)
    allowed_second = comprehend_usage_store.check_and_increment(usage_session, cap=2)

    assert allowed_first is True
    assert allowed_second is True
    assert comprehend_usage_store.get_count(usage_session) == 2


def test_check_and_increment_rejects_at_cap_without_incrementing_further(usage_session):
    comprehend_usage_store.check_and_increment(usage_session, cap=1)  # count -> 1
    rejected = comprehend_usage_store.check_and_increment(usage_session, cap=1)

    assert rejected is False
    # Still exactly 1 -- a rejected attempt must not keep bumping the count.
    assert comprehend_usage_store.get_count(usage_session) == 1


def test_check_and_increment_resets_naturally_on_a_new_date(usage_session):
    yesterday = date.today() - timedelta(days=1)
    today = date.today()

    # Peg yesterday's row at its cap.
    comprehend_usage_store.check_and_increment(usage_session, cap=1, today=yesterday)
    still_capped_yesterday = comprehend_usage_store.check_and_increment(
        usage_session, cap=1, today=yesterday
    )

    allowed_today = comprehend_usage_store.check_and_increment(
        usage_session, cap=1, today=today
    )

    assert still_capped_yesterday is False
    assert allowed_today is True  # a new date starts its own counter at 0
    assert comprehend_usage_store.get_count(usage_session, today=yesterday) == 1
    assert comprehend_usage_store.get_count(usage_session, today=today) == 1


# --- store unavailable: the fail-closed / fail-open split --------------------


def test_enqueue_fails_closed_when_the_cap_cannot_be_checked(usage_db, monkeypatch):
    """A genuine store failure (session obtained, query fails) rejects with 503
    and creates nothing.

    This guard exists for cost protection, so "can't verify the cap" must not
    quietly become "allow anyway" -- unlike the read-side catalog/progress
    helpers, which intentionally degrade for availability.
    """
    from sqlalchemy.exc import SQLAlchemyError

    def _broken_check_and_increment(*args, **kwargs):
        raise SQLAlchemyError("simulated DB failure")

    monkeypatch.setattr(
        comprehend_usage_store, "check_and_increment", _broken_check_and_increment
    )
    client = TestClient(main.app)

    resp = client.post("/comprehensions", json=_ENQUEUE_BODY)

    assert resp.status_code == 503


def test_reservation_fails_open_when_the_engine_was_never_initialized(monkeypatch):
    """When the engine was never initialized at all (``RuntimeError`` from
    ``new_session()``), the reservation degrades to "allow" rather than
    rejecting.

    Asserted against ``_reserve_daily_cap`` directly rather than through the
    endpoint, because an enqueue in this state fails a moment later anyway when
    it goes to write the row -- so the endpoint cannot show which of the two
    guards spoke. This branch is unreachable once the app has actually started:
    the lifespan handler always calls ``init_engine``, which assigns the
    session-factory global even when the ``CREATE TABLE`` probe fails against a
    down Postgres, so a live-but-unreachable database surfaces as
    ``SQLAlchemyError`` and takes the fail-closed branch above.

    ``_SessionLocal`` is forced to ``None`` because the engine is a
    process-wide global: an earlier test in this session may already have
    initialized it via ``_progress_engine``.
    """
    from app import db

    monkeypatch.setattr(db, "_SessionLocal", None)

    reserved = main._reserve_daily_cap()

    assert reserved == comprehend_usage_store.today_utc()
