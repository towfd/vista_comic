"""The line-analysis resource and its worker (web-line-analysis ticket 01).

Against the throwaway Postgres database (see ``conftest.py``), with the
``line_analysis`` and ``comprehend_usage`` tables truncated per test -- the
latter because every queued analysis reserves against the shared daily cap.

The worker is driven through ``process_pending`` directly, and Claude is
stubbed at ``line_analysis_client.analyse``: what the call itself sends is
``test_line_analysis_client.py``'s concern.
"""

from __future__ import annotations

from datetime import timedelta

import anthropic
import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app import (
    comprehend_usage_store,
    line_analysis_client,
    line_analysis_store,
    line_analysis_worker,
    main,
)

_BODY = {
    "sourceText": "Anh Dok-ja, viện phí đã thanh toán rồi à?",
    "translation": "獨子哥，住院費已經付了嗎？",
    "model": "sonnet",
    "names": [{"source": "Dok-ja", "target": "獨子"}],
}

_RESULT = {
    "words": [
        {"text": "Anh", "meaning": "哥", "partOfSpeech": "代名詞", "hanViet": "英", "note": ""},
        {"text": "Dok-ja", "meaning": "獨子", "partOfSpeech": "人名", "hanViet": "", "note": ""},
        {"text": "viện phí", "meaning": "住院費", "partOfSpeech": "名詞", "hanViet": "院費", "note": ""},
    ],
    "grammar": "主語省略……",
    "tone": "親近的確認語氣。",
}


@pytest.fixture
def client(line_analysis_db):
    return TestClient(main.app)


@pytest.fixture
def session(line_analysis_db):
    from app import db

    s = db.new_session()
    try:
        yield s
    finally:
        s.close()


@pytest.fixture
def claude(monkeypatch):
    """Replace the call: ``claude.answer`` is returned, or raised if an exception."""
    calls = []

    class _Claude:
        answer = _RESULT

    def analyse(**kwargs):
        calls.append(kwargs)
        if isinstance(_Claude.answer, BaseException):
            raise _Claude.answer
        return _Claude.answer

    monkeypatch.setattr(line_analysis_client, "analyse", analyse)
    _Claude.calls = calls
    return _Claude


def _post(client, **overrides):
    return client.post("/line-analyses", json={**_BODY, **overrides})


def _count(session) -> int:
    return comprehend_usage_store.get_count(session)


def _drain() -> int:
    return line_analysis_worker.process_pending()


# --- asking ------------------------------------------------------------------


def test_a_new_line_is_queued_pending_with_one_reservation(client, session):
    resp = _post(client)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "pending"
    assert body["model"] == "sonnet"
    assert body["sourceText"] == _BODY["sourceText"]
    assert body["translation"] == _BODY["translation"]
    assert body["result"] is None and body["failure"] is None
    assert body["updatedAt"]
    assert _count(session) == 1


def test_asking_again_while_pending_returns_the_same_analysis_and_reserves_nothing(client, session):
    first = _post(client).json()

    again = _post(client).json()

    assert again["id"] == first["id"]
    assert _count(session) == 1


def test_a_done_analysis_is_returned_as_it_is(client, session, claude):
    first = _post(client).json()
    _drain()

    again = _post(client).json()

    assert again["id"] == first["id"]
    assert again["status"] == "done"
    assert again["result"] == _RESULT
    assert len(claude.calls) == 1
    assert _count(session) == 1


def test_case_and_spacing_do_not_split_one_line(client, session):
    first = _post(client).json()

    again = _post(client, sourceText="ANH DOK-JA,  VIỆN PHÍ ĐÃ THANH TOÁN RỒI À?").json()

    assert again["id"] == first["id"]
    assert _count(session) == 1


def test_another_translation_or_model_is_another_analysis(client, session):
    first = _post(client).json()

    retranslated = _post(client, translation="獨子哥，住院費付清了嗎？").json()
    opus = _post(client, model="opus").json()

    assert len({first["id"], retranslated["id"], opus["id"]}) == 3
    assert _count(session) == 3


def test_refresh_requeues_a_done_analysis_with_one_reservation(client, session, claude):
    first = _post(client).json()
    _drain()

    refreshed = _post(client, refresh=True).json()

    assert refreshed["id"] == first["id"]
    assert refreshed["status"] == "pending"
    assert refreshed["result"] is None
    assert _count(session) == 2


def test_refresh_on_a_pending_analysis_changes_nothing(client, session):
    first = _post(client).json()

    again = _post(client, refresh=True).json()

    assert again["id"] == first["id"]
    assert again["status"] == "pending"
    assert _count(session) == 1


def test_a_failed_analysis_is_requeued_with_one_reservation(client, session, claude):
    first = _post(client).json()
    claude.answer = line_analysis_client.REFUSED
    _drain()
    assert _count(session) == 0  # the failure was refunded

    again = _post(client).json()

    assert again["id"] == first["id"]
    assert again["status"] == "pending"
    assert again["failure"] is None
    assert _count(session) == 1


def test_a_spent_cap_is_a_429_and_changes_nothing(client, session, monkeypatch, claude):
    first = _post(client).json()
    claude.answer = line_analysis_client.REFUSED
    _drain()
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 0)

    retry = _post(client)
    new = _post(client, model="fable")

    assert retry.status_code == 429
    assert new.status_code == 429
    row = line_analysis_store.get(session, first["id"])
    assert row.status == "failed"
    assert session.execute(text("SELECT count(*) FROM line_analysis")).scalar() == 1


def test_a_stored_analysis_is_still_returned_when_the_cap_is_spent(client, monkeypatch, claude):
    first = _post(client).json()
    _drain()
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 0)

    again = _post(client)

    assert again.status_code == 200
    assert again.json()["id"] == first["id"]


def test_a_line_with_no_text_or_an_unknown_model_is_rejected(client, session):
    assert _post(client, sourceText="   ").status_code == 422
    assert _post(client, model="haiku").status_code == 422
    assert _post(client, translation="").status_code == 422
    assert _count(session) == 0


# --- reading one -------------------------------------------------------------


def test_get_returns_one_analysis(client, claude):
    first = _post(client).json()
    _drain()

    resp = client.get(f"/line-analyses/{first['id']}")

    assert resp.status_code == 200
    assert resp.json()["status"] == "done"
    assert resp.json()["result"] == _RESULT


def test_get_is_404_when_missing(client):
    assert client.get("/line-analyses/999999").status_code == 404


# --- the worker --------------------------------------------------------------


def test_the_worker_sends_the_line_its_translation_names_and_model(client, claude):
    _post(client, model="opus")

    assert _drain() == 1

    [call] = claude.calls
    assert call["model"] == "opus"
    assert call["source_text"] == _BODY["sourceText"]
    assert call["translation"] == _BODY["translation"]
    assert call["names"] == [line_analysis_client.Name(source="Dok-ja", target="獨子")]


def test_a_running_analysis_still_reads_as_pending(client, session, claude):
    first = _post(client).json()
    line_analysis_store.claim_pending(session, limit=1)

    assert client.get(f"/line-analyses/{first['id']}").json()["status"] == "pending"


@pytest.mark.parametrize(
    "answer, failure",
    [
        (line_analysis_client.REFUSED, "refused"),
        (line_analysis_client.InvalidAnalysis("not JSON"), "invalid"),
        ({**_RESULT, "words": []}, "invalid"),
        ({**_RESULT, "words": [{**_RESULT["words"][0], "text": "bệnh viện"}]}, "invalid"),
        (
            anthropic.APIConnectionError(
                request=httpx.Request("POST", "https://api.anthropic.com")
            ),
            "error",
        ),
        (RuntimeError("CLAUDE_API_KEY is not set"), "error"),
    ],
)
def test_every_failure_is_recorded_with_its_reason_and_refunded(
    client, session, claude, answer, failure
):
    first = _post(client).json()
    claude.answer = answer

    _drain()

    body = client.get(f"/line-analyses/{first['id']}").json()
    assert body["status"] == "failed"
    assert body["failure"] == failure
    assert body["result"] is None
    assert _count(session) == 0


def test_a_refund_goes_back_to_the_day_it_was_reserved(client, session, claude):
    first = _post(client).json()
    yesterday = comprehend_usage_store.today_utc() - timedelta(days=1)
    session.execute(
        text("UPDATE line_analysis SET usage_date = :d WHERE id = :id"),
        {"d": yesterday, "id": first["id"]},
    )
    session.execute(
        text("INSERT INTO comprehend_usage (usage_date, request_count) VALUES (:d, 5)"),
        {"d": yesterday},
    )
    session.commit()
    claude.answer = line_analysis_client.REFUSED

    _drain()

    assert comprehend_usage_store.get_count(session, today=yesterday) == 4
    assert _count(session) == 1


def test_nothing_pending_means_nothing_runs(line_analysis_db, claude):
    assert _drain() == 0
    assert claude.calls == []


def test_a_restart_fails_interrupted_claims_and_refunds_them(client, session, claude):
    running = _post(client).json()
    waiting = _post(client, model="opus").json()
    session.execute(
        text("UPDATE line_analysis SET status = 'running' WHERE id = :id"),
        {"id": running["id"]},
    )
    session.commit()

    assert line_analysis_worker.release_orphans() == 1

    assert client.get(f"/line-analyses/{running['id']}").json()["failure"] == "interrupted"
    # A row still waiting its turn is not interrupted; the worker runs it next.
    assert client.get(f"/line-analyses/{waiting['id']}").json()["status"] == "pending"
    assert _count(session) == 1


# --- looking one up without asking for it ------------------------------------


def _lookup(client, **overrides):
    body = {k: v for k, v in {**_BODY, **overrides}.items() if k in ("sourceText", "translation", "model")}
    return client.post("/line-analyses/lookup", json=body)


def test_lookup_finds_a_stored_analysis_ignoring_case_and_spacing(client, claude):
    first = _post(client).json()
    _drain()

    resp = _lookup(client, sourceText="ANH DOK-JA,  VIỆN PHÍ ĐÃ THANH TOÁN RỒI À?")

    assert resp.status_code == 200
    assert resp.json()["id"] == first["id"]
    assert resp.json()["status"] == "done"


def test_lookup_is_404_and_queues_nothing_when_there_is_none(client, session, claude):
    assert _lookup(client).status_code == 404
    assert _lookup(client, model="fable").status_code == 404
    assert _lookup(client, sourceText="   ").status_code == 404

    assert session.execute(text("SELECT count(*) FROM line_analysis")).scalar() == 0
    assert _count(session) == 0
    assert claude.calls == []


def test_lookup_returns_a_pending_or_failed_analysis_as_it_is(client, session, claude):
    _post(client)
    assert _lookup(client).json()["status"] == "pending"

    claude.answer = line_analysis_client.REFUSED
    _drain()
    assert _lookup(client).json()["failure"] == "refused"
    assert _count(session) == 0
