"""Comprehension record store + endpoint tests (comprehension-response-ux).

Runs against a throwaway Postgres database (see ``conftest.py``); the
``comprehension_record`` and ``comprehend_usage`` tables are truncated before
each test, the latter because the daily cap is reserved at enqueue and a
leftover count would make cap assertions order-dependent.

Like ``test_translation.py``, no fixture library / catalog is needed for most
tests: the endpoints take an opaque source reference without validating it.
The title-join tests are the exception and build a catalog explicitly, since
that join is the one place these routes read the catalog at all.
"""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import SQLAlchemyError

from app import comprehend_usage_store, comprehension_store, main
from app.models import ChapterEntry, ComicEntry
from app.scanner import ScanReport

_BODY = {
    "sourceText": "À, trưởng phòng tìm cô.",
    "translatedText": "啊，主管在找妳。",
    "targetLanguage": "zh-Hant",
    "comicId": "deadbeefdeadbeef",
    "chapterId": "beefdeadbeefdead",
    "pageNumber": 12,
}


@pytest.fixture
def client(comprehension_db):
    return TestClient(main.app)


def _create(client, **overrides) -> dict:
    resp = client.post("/comprehensions", json={**_BODY, **overrides})
    assert resp.status_code == 201, resp.text
    return resp.json()


# --- enqueue -----------------------------------------------------------------


def test_enqueue_returns_a_pending_record_immediately(client):
    record = _create(client)

    # Pending, unread, and carrying only the on-device translation: the cloud
    # fields stay null until a worker fills them in.
    assert record["status"] == comprehension_store.STATUS_PENDING
    assert record["isRead"] is False
    assert record["translatedText"] == _BODY["translatedText"]
    assert record["cloudTranslation"] is None
    assert record["grammarNotes"] is None
    assert record["contextNotes"] is None
    assert record["toneRegister"] is None
    assert record["id"] > 0
    assert record["createdAt"]


def test_enqueue_defaults_to_the_cheaper_model_tier(client):
    assert _create(client)["useStrongerModel"] is False
    assert _create(client, useStrongerModel=True)["useStrongerModel"] is True


def test_enqueue_reserves_one_request_against_todays_cap(client, comprehension_session):
    before = comprehend_usage_store.get_count(comprehension_session)

    _create(client)

    assert comprehend_usage_store.get_count(comprehension_session) == before + 1


def test_enqueue_is_rejected_and_creates_nothing_once_the_cap_is_spent(
    client, comprehension_session, monkeypatch
):
    # The reader must learn the cap is gone at the moment they act, and must not
    # be left with a record in their history that can never complete.
    monkeypatch.setattr(comprehend_usage_store, "DAILY_CAP", 1)
    allowed = _create(client)

    resp = client.post("/comprehensions", json=_BODY)

    assert resp.status_code == 429
    # Only the request that was actually allowed left a row behind.
    assert [r["id"] for r in client.get("/comprehensions").json()] == [allowed["id"]]


@pytest.mark.parametrize(
    "missing_field",
    ["sourceText", "translatedText", "targetLanguage", "comicId", "chapterId"],
)
def test_enqueue_missing_required_field_is_rejected(client, missing_field):
    body = {k: v for k, v in _BODY.items() if k != missing_field}

    assert client.post("/comprehensions", json=body).status_code == 422


def test_enqueue_rejects_a_page_number_below_one(client):
    assert client.post("/comprehensions", json={**_BODY, "pageNumber": 0}).status_code == 422


# --- list / fetch ------------------------------------------------------------


def test_list_returns_records_newest_first(client):
    first = _create(client, sourceText="first")
    second = _create(client, sourceText="second")

    listed = client.get("/comprehensions").json()

    assert [r["id"] for r in listed] == [second["id"], first["id"]]


def test_list_is_empty_before_anything_is_enqueued(client):
    assert client.get("/comprehensions").json() == []


def test_fetch_one_returns_that_record(client):
    record = _create(client)

    fetched = client.get(f"/comprehensions/{record['id']}")

    assert fetched.status_code == 200
    assert fetched.json()["id"] == record["id"]


def test_fetch_unknown_record_is_404(client):
    assert client.get("/comprehensions/999999").status_code == 404


# --- read flag ---------------------------------------------------------------


def test_marking_read_flips_the_flag(client):
    record = _create(client)

    patched = client.patch(f"/comprehensions/{record['id']}", json={"isRead": True})

    assert patched.status_code == 200
    assert patched.json()["isRead"] is True
    assert client.get(f"/comprehensions/{record['id']}").json()["isRead"] is True


def test_marking_read_twice_is_not_an_error(client):
    # The caller is a screen reacting to being opened; it has no useful way to
    # handle "that was already read".
    record = _create(client)
    client.patch(f"/comprehensions/{record['id']}", json={"isRead": True})

    again = client.patch(f"/comprehensions/{record['id']}", json={"isRead": True})

    assert again.status_code == 200
    assert again.json()["isRead"] is True


def test_read_flag_can_be_put_back(client):
    record = _create(client)
    client.patch(f"/comprehensions/{record['id']}", json={"isRead": True})

    unread = client.patch(f"/comprehensions/{record['id']}", json={"isRead": False})

    assert unread.json()["isRead"] is False


def test_patching_unknown_record_is_404(client):
    assert client.patch("/comprehensions/999999", json={"isRead": True}).status_code == 404


# --- retry -------------------------------------------------------------------


def _force_status(session, record_id: int, status: str) -> None:
    """Stand in for the worker, which does not exist yet at this ticket."""
    row = comprehension_store.get(session, record_id)
    row.status = status
    session.commit()


def test_retry_returns_a_failed_record_to_pending(client, comprehension_session):
    record = _create(client)
    _force_status(comprehension_session, record["id"], comprehension_store.STATUS_FAILED)

    resp = client.post(f"/comprehensions/{record['id']}/retry")

    assert resp.status_code == 200
    assert resp.json()["status"] == comprehension_store.STATUS_PENDING


def test_retry_reserves_another_request(client, comprehension_session):
    record = _create(client)
    _force_status(comprehension_session, record["id"], comprehension_store.STATUS_FAILED)
    before = comprehend_usage_store.get_count(comprehension_session)

    client.post(f"/comprehensions/{record['id']}/retry")

    assert comprehend_usage_store.get_count(comprehension_session) == before + 1


@pytest.mark.parametrize(
    "status",
    [
        comprehension_store.STATUS_PENDING,
        comprehension_store.STATUS_RUNNING,
        comprehension_store.STATUS_OK,
        comprehension_store.STATUS_DECLINED,
    ],
)
def test_retry_is_refused_for_any_status_other_than_failed(
    client, comprehension_session, status
):
    # 409, not 404: "that isn't retryable" is a different mistake from "that
    # isn't there", and only one of them means "look again in a moment".
    record = _create(client)
    _force_status(comprehension_session, record["id"], status)

    assert client.post(f"/comprehensions/{record['id']}/retry").status_code == 409


def test_refused_retry_does_not_consume_a_request(client, comprehension_session):
    record = _create(client)
    before = comprehend_usage_store.get_count(comprehension_session)

    client.post(f"/comprehensions/{record['id']}/retry")  # still pending → 409

    assert comprehend_usage_store.get_count(comprehension_session) == before


def test_retry_of_unknown_record_is_404(client):
    assert client.post("/comprehensions/999999/retry").status_code == 404


# --- delete ------------------------------------------------------------------


def test_delete_removes_the_record(client):
    record = _create(client)

    assert client.delete(f"/comprehensions/{record['id']}").status_code == 204
    assert client.get(f"/comprehensions/{record['id']}").status_code == 404


def test_deleting_a_pending_record_refunds_its_reservation(
    client, comprehension_session
):
    # It was paid for but never spent, so the budget comes back.
    before = comprehend_usage_store.get_count(comprehension_session)
    record = _create(client)
    assert comprehend_usage_store.get_count(comprehension_session) == before + 1

    client.delete(f"/comprehensions/{record['id']}")

    assert comprehend_usage_store.get_count(comprehension_session) == before


@pytest.mark.parametrize(
    "status",
    [
        comprehension_store.STATUS_OK,
        comprehension_store.STATUS_DECLINED,
        comprehension_store.STATUS_FAILED,
    ],
)
def test_deleting_a_finished_record_does_not_refund(
    client, comprehension_session, status
):
    # Anything that reached Claude keeps its count -- including a declined
    # result, which produced billable tokens.
    record = _create(client)
    _force_status(comprehension_session, record["id"], status)
    spent = comprehend_usage_store.get_count(comprehension_session)

    client.delete(f"/comprehensions/{record['id']}")

    assert comprehend_usage_store.get_count(comprehension_session) == spent


def test_delete_of_unknown_record_is_404(client):
    assert client.delete("/comprehensions/999999").status_code == 404


def test_refund_returns_to_the_day_the_reservation_was_drawn_from(
    comprehension_session,
):
    # The cap is keyed by UTC day, so a row reserved just before midnight and
    # released just after must refund to *yesterday* -- refunding to "today"
    # would silently hand the new day an extra request.
    yesterday = comprehend_usage_store.today_utc() - timedelta(days=1)
    comprehend_usage_store.check_and_increment(comprehension_session, today=yesterday)
    assert comprehend_usage_store.get_count(comprehension_session, today=yesterday) == 1

    comprehend_usage_store.refund(comprehension_session, usage_date=yesterday)

    assert comprehend_usage_store.get_count(comprehension_session, today=yesterday) == 0
    assert comprehend_usage_store.get_count(comprehension_session) == 0


def test_refund_never_manufactures_budget(comprehension_session):
    today = comprehend_usage_store.today_utc()
    comprehend_usage_store.check_and_increment(comprehension_session, today=today)

    comprehend_usage_store.refund(comprehension_session, usage_date=today)
    comprehend_usage_store.refund(comprehension_session, usage_date=today)

    assert comprehend_usage_store.get_count(comprehension_session, today=today) == 0


def test_a_store_failure_at_enqueue_gives_the_reservation_back(
    client, comprehension_session, monkeypatch
):
    # The inverse of the cap case, and the easier one to get wrong: the cap was
    # reserved before the row was attempted, so a store failure must not burn a
    # request that never became work.
    def boom(*args, **kwargs):
        raise SQLAlchemyError("store down")

    monkeypatch.setattr(comprehension_store, "insert_record", boom)
    before = comprehend_usage_store.get_count(comprehension_session)

    resp = client.post("/comprehensions", json=_BODY)

    assert resp.status_code == 503
    assert comprehend_usage_store.get_count(comprehension_session) == before


def test_a_store_failure_surfaces_rather_than_looking_empty(client, monkeypatch):
    # Never degrade a read failure into an empty list: "unreachable" must not be
    # reported as "you have no history", which the reader cannot tell apart.
    def boom(*args, **kwargs):
        raise SQLAlchemyError("store down")

    monkeypatch.setattr(comprehension_store, "list_all", boom)

    resp = client.get("/comprehensions")

    assert resp.status_code == 503


def test_refund_for_a_day_with_no_row_is_a_no_op(comprehension_session):
    never_used = date(2000, 1, 1)

    comprehend_usage_store.refund(comprehension_session, usage_date=never_used)

    assert comprehend_usage_store.get_count(comprehension_session, today=never_used) == 0


# --- title join --------------------------------------------------------------


def _catalog_with(comic_id: str, chapter_id: str):
    """Minimal in-memory catalog holding one comic with one chapter."""
    return main.Catalog.build(
        comics=[
            ComicEntry(
                id=comic_id,
                title="marrymyhusband",
                cover_path=None,
                chapters=[
                    ChapterEntry(
                        id=chapter_id, number=1, title="bai1", page_paths=["a.jpg"]
                    )
                ],
            )
        ],
        report=ScanReport(),
        root=Path("/library"),
    )


def test_records_carry_comic_and_chapter_titles_from_the_catalog(
    client, monkeypatch
):
    # The row stores path-hash ids, which are correct as keys and useless as
    # labels on a list the reader browses.
    monkeypatch.setattr(
        main.state, "catalog", _catalog_with(_BODY["comicId"], _BODY["chapterId"])
    )

    record = _create(client)

    assert record["comicTitle"] == "marrymyhusband"
    assert record["chapterTitle"] == "bai1"
    assert client.get("/comprehensions").json()[0]["comicTitle"] == "marrymyhusband"


def test_titles_are_null_for_a_comic_no_longer_in_the_library(client, monkeypatch):
    # Deleting a folder must not corrupt history: the record stays readable and
    # the null title is the client's cue that jumping to source would fail.
    monkeypatch.setattr(main.state, "catalog", _catalog_with("other", "other"))

    record = _create(client)

    assert record["comicTitle"] is None
    assert record["chapterTitle"] is None


def test_history_is_still_listable_when_the_catalog_is_unavailable(client, monkeypatch):
    # Titles are decoration; the records are the data. A failed library scan
    # must not take the reader's history down with it.
    _create(client)
    monkeypatch.setattr(main.state, "catalog", None)

    listed = client.get("/comprehensions")

    assert listed.status_code == 200
    assert listed.json()[0]["comicTitle"] is None
