"""Tests for ``POST /comprehend``'s two anomaly guards (ticket 12):

1. Image-size ceiling -- rejects an oversized crop/page image with 413,
   before any Claude call. Pure request-shape validation, no DB involved, so
   it stubs the Claude client (mirrors ``test_comprehension.py``) but does
   NOT need a database -- these tests always run, even in environments where
   Postgres is unreachable.
2. Global daily request cap -- rejects with 429 once the cap is reached,
   before any Claude call, backed by the new ``comprehend_usage`` table (see
   ``comprehend_usage_store.py``). These tests need a real throwaway Postgres
   database (mirrors ``test_progress.py``/``test_translation.py``'s
   ``_progress_engine`` fixture) and, in an environment where that database is
   unreachable, will error the same way the rest of this suite's DB-backed
   tests already do (see ``conftest.py``'s module docstring) -- that is a
   known, pre-existing environment limitation, not a new kind of failure.

The size-ceiling test injects a small effective ceiling (rather than sending a
literally oversized payload) and the cap tests inject a small effective cap
(rather than sending 300 real requests), per the ticket's acceptance
criteria.
"""

from __future__ import annotations

from datetime import date, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app import comprehend_usage_store, comprehension_client, main

_BODY = {
    "cropImageBase64": "Y3JvcA==",
    "pageImageBase64": "cGFnZQ==",
    "sourceText": "Xin chào",
    "targetLanguageCode": "zh-Hant",
}


def _tool_use_block(**input_fields):
    return SimpleNamespace(
        type="tool_use",
        name=comprehension_client._TOOL_NAME,
        input=input_fields,
    )


class _FakeMessages:
    def __init__(self, *, blocks=None):
        self._blocks = blocks if blocks is not None else []
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(content=self._blocks)


class _FakeClient:
    def __init__(self, *, blocks=None):
        self.messages = _FakeMessages(blocks=blocks)


def _stub_client(monkeypatch, *, blocks=None) -> _FakeClient:
    """Replace ``comprehension_client._client`` so no real API key/network is used."""
    fake = _FakeClient(blocks=blocks)
    monkeypatch.setattr(comprehension_client, "_client", lambda: fake)
    return fake


def _ok_block() -> SimpleNamespace:
    return _tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )


# --- image-size ceiling: no DB required --------------------------------------
#
# ``TestClient(main.app)`` built directly (no lifespan), same rationale as
# test_comprehension.py's `client` fixture: /comprehend never touches the
# catalog, and these two tests don't touch the DB-backed cap guard either
# (the size guard runs first and rejects before the cap guard would even open
# a session).


@pytest.fixture
def client():
    return TestClient(main.app)


def test_oversized_crop_image_rejected_413_before_claude_call(client, monkeypatch):
    monkeypatch.setattr(main, "_MAX_IMAGE_BASE64_CHARS", 100)
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])
    oversized = "A" * 101

    resp = client.post("/comprehend", json={**_BODY, "cropImageBase64": oversized})

    assert resp.status_code == 413
    assert resp.json()["detail"]
    assert fake.messages.calls == []


def test_oversized_page_image_rejected_413_before_claude_call(client, monkeypatch):
    monkeypatch.setattr(main, "_MAX_IMAGE_BASE64_CHARS", 100)
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])
    oversized = "A" * 101

    resp = client.post("/comprehend", json={**_BODY, "pageImageBase64": oversized})

    assert resp.status_code == 413
    assert fake.messages.calls == []


def test_image_within_ceiling_is_not_rejected_by_size_guard(client, monkeypatch):
    monkeypatch.setattr(main, "_MAX_IMAGE_BASE64_CHARS", 100)
    monkeypatch.setattr(
        main,
        "_guard_daily_cap",
        lambda: None,  # isolate: only the size guard is under test here
    )
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])
    within_ceiling = "A" * 100

    resp = client.post(
        "/comprehend",
        json={**_BODY, "cropImageBase64": within_ceiling, "pageImageBase64": within_ceiling},
    )

    assert resp.status_code == 200
    assert len(fake.messages.calls) == 1


# --- daily cap: store-level -----------------------------------------------------


@pytest.fixture
def usage_db(_progress_engine):
    """Truncate the ``comprehend_usage`` table before each test that uses it.

    Mirrors ``conftest.py``'s ``progress_db``/``translation_db`` fixtures,
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


# --- daily cap: endpoint-level ----------------------------------------------


@pytest.fixture
def cap_client(usage_db):
    return TestClient(main.app)


def test_comprehend_allows_requests_under_the_daily_cap(cap_client, monkeypatch):
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 2)
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    first = cap_client.post("/comprehend", json=_BODY)
    second = cap_client.post("/comprehend", json=_BODY)

    assert first.status_code == 200
    assert second.status_code == 200
    assert len(fake.messages.calls) == 2


def test_comprehend_rejects_429_once_daily_cap_exceeded_before_claude_call(
    cap_client, monkeypatch
):
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 1)
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    first = cap_client.post("/comprehend", json=_BODY)
    second = cap_client.post("/comprehend", json=_BODY)

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["detail"]
    # Only the first (allowed) request ever reached Claude.
    assert len(fake.messages.calls) == 1


def test_comprehend_rejects_429_when_cap_pre_seeded_at_limit(cap_client, monkeypatch, usage_session):
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 5)
    # Pre-seed today's count directly at the cap, per the ticket's alternative
    # to monkeypatching a low cap.
    comprehend_usage_store.check_and_increment(usage_session, cap=5)
    comprehend_usage_store.check_and_increment(usage_session, cap=5)
    comprehend_usage_store.check_and_increment(usage_session, cap=5)
    comprehend_usage_store.check_and_increment(usage_session, cap=5)
    comprehend_usage_store.check_and_increment(usage_session, cap=5)
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = cap_client.post("/comprehend", json=_BODY)

    assert resp.status_code == 429
    assert fake.messages.calls == []


# --- daily cap: store-unavailable fail-closed/fail-open split ----------------


def test_comprehend_daily_cap_fails_closed_on_sqlalchemy_error(
    cap_client, monkeypatch
):
    """A genuine store failure (session obtained, query fails) rejects (503),
    never reaching Claude -- this guard's whole purpose is cost protection.
    """
    from sqlalchemy.exc import SQLAlchemyError

    def _broken_check_and_increment(*args, **kwargs):
        raise SQLAlchemyError("simulated DB failure")

    monkeypatch.setattr(
        comprehend_usage_store, "check_and_increment", _broken_check_and_increment
    )
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = cap_client.post("/comprehend", json=_BODY)

    assert resp.status_code == 503
    assert fake.messages.calls == []


def test_comprehend_daily_cap_fails_open_when_engine_never_initialized(monkeypatch):
    """When the engine was never initialized at all (RuntimeError from
    new_session()) -- the state test_comprehension.py's own ticket-11 tests
    run in, since they build TestClient(app) without the startup lifespan --
    the cap guard degrades to "allow" rather than rejecting every
    comprehension request over a codepath that cannot occur once the app has
    actually started (see main._guard_daily_cap's docstring).

    ``_SessionLocal`` is forced to ``None`` (mirrors
    ``test_translation.py``'s ``..._503_when_store_unavailable`` tests)
    because the module-level engine is a process-wide global: an earlier test
    in this session may already have initialized it via ``_progress_engine``,
    which would otherwise make ``new_session()`` succeed here regardless of
    this test's intent.
    """
    from app import db

    monkeypatch.setattr(db, "_SessionLocal", None)
    client = TestClient(main.app)  # no lifespan -> doesn't re-initialize it
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert len(fake.messages.calls) == 1
