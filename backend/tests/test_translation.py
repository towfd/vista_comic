"""Saved-translation store + endpoint tests (ocr-translation ticket 02, "單字本").

Runs against a throwaway Postgres database (see ``conftest.py``); the
``saved_translation`` table is truncated before each test. Unlike
``test_progress.py``, these tests do not need a fixture library / catalog: the
save/list endpoints take an opaque source reference (comic/chapter id, page
number) without validating it against the catalog (see ``main.py``'s
``save_translation``/``list_translations``), so ``TestClient(main.app)`` is
built without ``main.load_catalog`` first.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import main, translation_store

_SAMPLE = dict(
    original_text="Xin chào",
    translated_text="你好",
    target_language="zh-Hant",
    comic_id="deadbeefdeadbeef",
    chapter_id="beefdeadbeefdead",
    page_number=1,
)

_SAMPLE_BODY = {
    "originalText": "Xin chào",
    "translatedText": "你好",
    "targetLanguage": "zh-Hant",
    "comicId": "deadbeefdeadbeef",
    "chapterId": "beefdeadbeefdead",
    "pageNumber": 1,
}


@pytest.fixture
def client(translation_db):
    return TestClient(main.app)


# --- store-level --------------------------------------------------------------


def test_insert_translation_returns_id_and_saved_at(translation_session):
    row = translation_store.insert_translation(translation_session, **_SAMPLE)
    assert row.id is not None
    assert row.saved_at is not None
    assert row.original_text == "Xin chào"
    assert row.translated_text == "你好"


def test_list_all_returns_inserted_rows_most_recent_first(translation_session):
    first = translation_store.insert_translation(translation_session, **_SAMPLE)
    second = translation_store.insert_translation(
        translation_session, **{**_SAMPLE, "original_text": "Cảm ơn"}
    )
    rows = translation_store.list_all(translation_session)
    assert [r.id for r in rows] == [second.id, first.id]


def test_list_all_empty_when_nothing_saved(translation_session):
    assert translation_store.list_all(translation_session) == []


# --- endpoint: POST -----------------------------------------------------------


def test_post_translation_returns_saved_entry(client):
    resp = client.post("/translations", json=_SAMPLE_BODY)
    assert resp.status_code == 200
    body = resp.json()
    assert set(body) == {
        "id",
        "originalText",
        "translatedText",
        "targetLanguage",
        "comicId",
        "chapterId",
        "pageNumber",
        "savedAt",
    }
    assert body["originalText"] == "Xin chào"
    assert body["translatedText"] == "你好"
    assert body["targetLanguage"] == "zh-Hant"
    assert body["comicId"] == "deadbeefdeadbeef"
    assert body["chapterId"] == "beefdeadbeefdead"
    assert body["pageNumber"] == 1
    assert body["savedAt"].endswith("+00:00")  # ISO-8601 UTC
    assert isinstance(body["id"], int)


@pytest.mark.parametrize("bad_page", [0, -1])
def test_post_non_positive_page_number_422(client, bad_page):
    resp = client.post("/translations", json={**_SAMPLE_BODY, "pageNumber": bad_page})
    assert resp.status_code == 422


def test_post_missing_field_422(client):
    body = {k: v for k, v in _SAMPLE_BODY.items() if k != "translatedText"}
    resp = client.post("/translations", json=body)
    assert resp.status_code == 422


# --- endpoint: GET --------------------------------------------------------------


def test_get_translations_empty_list_initially(client):
    resp = client.get("/translations")
    assert resp.status_code == 200
    assert resp.json() == []


def test_get_translations_lists_saved_entries(client):
    client.post("/translations", json=_SAMPLE_BODY)
    client.post(
        "/translations", json={**_SAMPLE_BODY, "originalText": "Cảm ơn", "translatedText": "謝謝"}
    )
    resp = client.get("/translations")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    # Most recently saved first.
    assert body[0]["originalText"] == "Cảm ơn"
    assert body[1]["originalText"] == "Xin chào"


def test_save_then_list_round_trips_all_fields(client):
    saved = client.post("/translations", json=_SAMPLE_BODY).json()
    listed = client.get("/translations").json()
    assert len(listed) == 1
    assert listed[0] == saved


# --- resilience: store unavailable ---------------------------------------------


def test_post_translation_503_when_store_unavailable(client, monkeypatch):
    from app import db

    monkeypatch.setattr(db, "_SessionLocal", None)
    resp = client.post("/translations", json=_SAMPLE_BODY)
    assert resp.status_code == 503


def test_get_translations_503_when_store_unavailable(client, monkeypatch):
    """Unlike the catalog/progress read paths, listing does NOT degrade to []:

    there is no non-DB origin for saved translations, so an outage must be
    reported (503), not silently presented as "nothing saved".
    """
    from app import db

    monkeypatch.setattr(db, "_SessionLocal", None)
    resp = client.get("/translations")
    assert resp.status_code == 503


# --- endpoint: DELETE -----------------------------------------------------------


def test_delete_translation_returns_204_and_removes_it(client):
    saved = client.post("/translations", json=_SAMPLE_BODY).json()

    resp = client.delete(f"/translations/{saved['id']}")
    assert resp.status_code == 204

    listed = client.get("/translations").json()
    assert listed == []


def test_delete_translation_only_removes_the_targeted_row(client):
    first = client.post("/translations", json=_SAMPLE_BODY).json()
    second = client.post(
        "/translations", json={**_SAMPLE_BODY, "originalText": "Cảm ơn"}
    ).json()

    resp = client.delete(f"/translations/{first['id']}")
    assert resp.status_code == 204

    listed = client.get("/translations").json()
    assert [row["id"] for row in listed] == [second["id"]]


def test_delete_unknown_translation_404(client):
    resp = client.delete("/translations/999999")
    assert resp.status_code == 404


def test_delete_translation_503_when_store_unavailable(client, monkeypatch):
    from app import db

    monkeypatch.setattr(db, "_SessionLocal", None)
    resp = client.delete("/translations/1")
    assert resp.status_code == 503
