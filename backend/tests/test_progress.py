"""Reading-progress store + endpoint tests (Slice 4).

Runs against a throwaway Postgres database (see ``conftest.py``); the
``progress`` table is truncated before each test. The catalog is a temporary
fixture library, never the real ``MANGA_LIBRARY_PATH``.

Chapter map for the ``sample_library`` fixture:

    Alpha/01 - The Journey  -> 2 pages
    Alpha/02                -> 1 page
    Beta/01-intro           -> 3 pages
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import main, progress_store
from app.ids import stable_id

ALPHA = stable_id("Alpha")
BETA = stable_id("Beta")
JOURNEY = stable_id("Alpha/01 - The Journey")  # pageCount 2
CH_TWO = stable_id("Alpha/02")  # pageCount 1
INTRO = stable_id("Beta/01-intro")  # pageCount 3


@pytest.fixture
def client(sample_library, progress_db):
    catalog = main.load_catalog(sample_library)
    assert catalog.comics, "fixture catalog should not be empty"
    return TestClient(main.app)


def _progress_path(comic_id: str, chapter_id: str) -> str:
    return f"/comics/{comic_id}/chapters/{chapter_id}/progress"


# --- store-level ------------------------------------------------------------


def test_upsert_is_idempotent_and_refreshes(db_session):
    first = progress_store.upsert(db_session, ALPHA, JOURNEY, 1, 2)
    second = progress_store.upsert(db_session, ALPHA, JOURNEY, 2, 2)

    rows = progress_store.progress_by_chapter(db_session, ALPHA)
    assert list(rows) == [JOURNEY], "two upserts of one chapter -> exactly one row"
    assert rows[JOURNEY].last_page == 2
    assert second >= first  # updated_at refreshed (DB clock, never goes back)


def test_read_state_helper_boundaries():
    assert progress_store.read_state(None, 2) == "unread"
    assert progress_store.read_state(1, 2) == "reading"
    assert progress_store.read_state(2, 2) == "read"
    assert progress_store.read_state(3, 2) == "read"  # >= counts as read


# --- endpoint: PUT ----------------------------------------------------------


def test_put_progress_returns_echoed_body(client):
    resp = client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1})
    assert resp.status_code == 200
    body = resp.json()
    assert set(body) == {"comicId", "chapterId", "lastPage", "pageCount", "updatedAt"}
    assert body["comicId"] == ALPHA
    assert body["chapterId"] == JOURNEY
    assert body["lastPage"] == 1
    assert body["pageCount"] == 2
    assert body["updatedAt"].endswith("+00:00")  # ISO-8601 UTC


def test_put_unknown_comic_404(client):
    resp = client.put(_progress_path("deadbeefdeadbeef", JOURNEY), json={"lastPage": 1})
    assert resp.status_code == 404


def test_put_unknown_chapter_404(client):
    resp = client.put(_progress_path(ALPHA, "deadbeefdeadbeef"), json={"lastPage": 1})
    assert resp.status_code == 404


def test_put_chapter_of_other_comic_404(client):
    # INTRO belongs to Beta, not Alpha.
    resp = client.put(_progress_path(ALPHA, INTRO), json={"lastPage": 1})
    assert resp.status_code == 404


@pytest.mark.parametrize("bad_page", [0, -1, 3, 99])
def test_put_out_of_range_page_422(client, bad_page):
    # JOURNEY has 2 pages; anything outside [1, 2] is rejected.
    resp = client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": bad_page})
    assert resp.status_code == 422


def test_put_non_integer_page_422(client):
    resp = client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": "nope"})
    assert resp.status_code == 422


# --- endpoint: readState derivation -----------------------------------------


def test_read_state_unread_when_no_row(client):
    detail = client.get(f"/comics/{ALPHA}").json()
    states = {ch["id"]: ch["readState"] for ch in detail["chapters"]}
    assert states[JOURNEY] == "unread"
    assert states[CH_TWO] == "unread"


def test_read_state_reading_when_partial(client):
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1})
    detail = client.get(f"/comics/{ALPHA}").json()
    states = {ch["id"]: ch["readState"] for ch in detail["chapters"]}
    assert states[JOURNEY] == "reading"
    assert states[CH_TWO] == "unread"


def test_read_state_read_when_at_last_page(client):
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 2})
    detail = client.get(f"/comics/{ALPHA}").json()
    states = {ch["id"]: ch["readState"] for ch in detail["chapters"]}
    assert states[JOURNEY] == "read"


# --- endpoint: lastReadPage -------------------------------------------------


def test_last_read_page_absent_before_and_present_after(client):
    before = client.get(f"/comics/{ALPHA}/chapters/{JOURNEY}").json()
    assert "lastReadPage" not in before  # omitted when no progress

    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 2})

    after = client.get(f"/comics/{ALPHA}/chapters/{JOURNEY}").json()
    assert after["lastReadPage"] == 2


# --- endpoint: lastReadAt aggregation ---------------------------------------


def test_last_read_at_is_max_across_chapters(client):
    first = client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1}).json()
    second = client.put(_progress_path(ALPHA, CH_TWO), json={"lastPage": 1}).json()
    assert second["updatedAt"] >= first["updatedAt"]

    comics = {c["id"]: c for c in client.get("/comics").json()}
    # Alpha's lastReadAt is the max updated_at across its two touched chapters.
    assert comics[ALPHA]["lastReadAt"] == second["updatedAt"]
    # Beta has no progress -> null.
    assert comics[BETA]["lastReadAt"] is None


# --- resilience: catalog is independent of the progress store ---------------


def test_catalog_endpoints_degrade_when_store_unavailable(client, monkeypatch):
    """A progress-DB outage must not break catalog browsing or the reader.

    The catalog is scan-derived and in memory, so reads degrade to "no
    progress" (readState unread, lastReadAt null, lastReadPage omitted) rather
    than 500. A write, which cannot silently succeed, returns 503.
    """
    from app import db

    # Simulate the store being unreachable (engine never initialised).
    monkeypatch.setattr(db, "_SessionLocal", None)

    comics = client.get("/comics")
    assert comics.status_code == 200
    assert all(c["lastReadAt"] is None for c in comics.json())

    detail = client.get(f"/comics/{ALPHA}")
    assert detail.status_code == 200
    assert all(ch["readState"] == "unread" for ch in detail.json()["chapters"])

    chapter = client.get(f"/comics/{ALPHA}/chapters/{JOURNEY}")
    assert chapter.status_code == 200
    assert "lastReadPage" not in chapter.json()

    saved = client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1})
    assert saved.status_code == 503


# --- persistence across a rescan --------------------------------------------


def test_progress_survives_rescan(client, sample_library):
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1})

    # Re-scan the library: catalog is rebuilt, IDs are path-derived and stable,
    # so the stored progress row still joins to the same chapter.
    main.load_catalog(sample_library)

    detail = client.get(f"/comics/{ALPHA}").json()
    states = {ch["id"]: ch["readState"] for ch in detail["chapters"]}
    assert states[JOURNEY] == "reading"
