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

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import main, progress_store
from app.db import Progress
from app.ids import stable_id
from app.models import ChapterEntry

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


# --- continueChapterId: selection algorithm (pure function) -----------------

_T0 = datetime(2026, 1, 1, tzinfo=timezone.utc)


def _chapter(rel: str, number: int, pages: int) -> ChapterEntry:
    return ChapterEntry(
        id=stable_id(rel),
        number=number,
        title=f"Chapter {number}",
        page_paths=[f"{rel}/{i}.jpg" for i in range(pages)],
    )


def _row(chapter: ChapterEntry, last_page: int, minutes: int) -> Progress:
    return Progress(
        comic_id="c",
        chapter_id=chapter.id,
        last_page=last_page,
        page_count=chapter.page_count,
        updated_at=_T0 + timedelta(minutes=minutes),
    )


def test_continue_picks_latest_reading_chapter():
    ch1 = _chapter("C/01", 1, 3)
    ch2 = _chapter("C/02", 2, 3)
    # Both are "reading" (last_page < page_count); ch2 was read more recently.
    rows = {
        ch1.id: _row(ch1, 1, minutes=0),
        ch2.id: _row(ch2, 1, minutes=5),
    }
    assert progress_store.continue_chapter_id([ch1, ch2], rows) == ch2.id


def test_continue_ignores_read_chapter_even_when_more_recent():
    ch1 = _chapter("C/01", 1, 3)
    ch2 = _chapter("C/02", 2, 3)
    # ch1 is reading (earlier); ch2 is fully read (later). Read must not win.
    rows = {
        ch1.id: _row(ch1, 1, minutes=0),
        ch2.id: _row(ch2, 3, minutes=5),  # last_page == page_count -> read
    }
    assert progress_store.continue_chapter_id([ch1, ch2], rows) == ch1.id


def test_continue_first_unread_when_none_reading():
    ch1 = _chapter("C/01", 1, 3)
    ch2 = _chapter("C/02", 2, 3)
    ch3 = _chapter("C/03", 3, 3)
    # ch1 read; ch2 has no row (first unread) -> ch2 wins over later ch3.
    rows = {ch1.id: _row(ch1, 3, minutes=0)}
    assert progress_store.continue_chapter_id([ch1, ch2, ch3], rows) == ch2.id


def test_continue_first_chapter_when_all_read():
    ch1 = _chapter("C/01", 1, 3)
    ch2 = _chapter("C/02", 2, 3)
    rows = {
        ch1.id: _row(ch1, 3, minutes=0),
        ch2.id: _row(ch2, 3, minutes=5),
    }
    assert progress_store.continue_chapter_id([ch1, ch2], rows) == ch1.id


def test_continue_first_chapter_when_no_progress():
    ch1 = _chapter("C/01", 1, 3)
    ch2 = _chapter("C/02", 2, 3)
    assert progress_store.continue_chapter_id([ch1, ch2], {}) == ch1.id


# --- continueChapterId: over the /comics endpoint ---------------------------


def test_comics_continue_present_and_defaults_to_first_chapter(client):
    comics = {c["id"]: c for c in client.get("/comics").json()}
    # Always present on every item; brand-new comics point at their first chapter.
    assert all("continueChapterId" in c for c in comics.values())
    assert comics[ALPHA]["continueChapterId"] == JOURNEY
    assert comics[BETA]["continueChapterId"] == INTRO


def test_comics_continue_is_the_reading_chapter(client):
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 1})
    comics = {c["id"]: c for c in client.get("/comics").json()}
    assert comics[ALPHA]["continueChapterId"] == JOURNEY


def test_comics_continue_first_unread_when_a_chapter_is_read(client):
    # JOURNEY fully read; CH_TWO untouched -> Continue jumps to CH_TWO.
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 2})
    comics = {c["id"]: c for c in client.get("/comics").json()}
    assert comics[ALPHA]["continueChapterId"] == CH_TWO


def test_comics_continue_first_chapter_when_all_read(client):
    client.put(_progress_path(ALPHA, JOURNEY), json={"lastPage": 2})
    client.put(_progress_path(ALPHA, CH_TWO), json={"lastPage": 1})
    comics = {c["id"]: c for c in client.get("/comics").json()}
    assert comics[ALPHA]["continueChapterId"] == JOURNEY


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
    body = comics.json()
    assert all(c["lastReadAt"] is None for c in body)
    # No progress visible -> Continue degrades to each comic's first chapter.
    by_id = {c["id"]: c for c in body}
    assert by_id[ALPHA]["continueChapterId"] == JOURNEY
    assert by_id[BETA]["continueChapterId"] == INTRO

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
