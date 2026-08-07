"""HTTP endpoint tests using FastAPI's TestClient against a fixture catalog.

The app is backed by a temporary fixture library (via ``main.load_catalog``),
never the real ``MANGA_LIBRARY_PATH``. The client is *not* used as a context
manager, so the startup lifespan (which would scan the real library) never runs.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import main
from app.ids import stable_id


@pytest.fixture
def client(sample_library, progress_db):
    catalog = main.load_catalog(sample_library)
    assert catalog.comics, "fixture catalog should not be empty"
    return TestClient(main.app)


def test_list_comics_shape_and_counts(client):
    resp = client.get("/comics")
    assert resp.status_code == 200

    comics = resp.json()
    assert [c["title"] for c in comics] == ["Alpha", "Beta"]

    alpha = comics[0]
    assert set(alpha) == {
        "id",
        "title",
        "coverUrl",
        "chapterCount",
        "lastReadAt",
        "continueChapterId",
    }
    assert alpha["id"] == stable_id("Alpha")
    assert alpha["chapterCount"] == 2
    # coverUrl is now an absolute URL derived from the request origin.
    assert alpha["coverUrl"] == f"http://testserver/media/{stable_id('Alpha')}/cover"
    assert alpha["lastReadAt"] is None
    # No progress yet -> Continue points at the first chapter (reading order).
    assert alpha["continueChapterId"] == stable_id("Alpha/01 - The Journey")


def test_get_comic_detail_shape_and_counts(client):
    comic_id = stable_id("Alpha")
    resp = client.get(f"/comics/{comic_id}")
    assert resp.status_code == 200

    detail = resp.json()
    assert set(detail) == {"id", "title", "coverUrl", "chapters"}
    assert detail["id"] == comic_id
    assert detail["title"] == "Alpha"
    assert len(detail["chapters"]) == 2

    ch = detail["chapters"][0]
    assert set(ch) == {"id", "number", "title", "pageCount", "readState", "coverUrl"}
    assert ch["number"] == 1
    assert ch["title"] == "The Journey"
    assert ch["pageCount"] == 2
    assert ch["readState"] == "unread"  # always unread in v1
    assert ch["id"] == stable_id("Alpha/01 - The Journey")


def test_a_chapters_own_cover_is_advertised_and_is_not_a_page(client):
    comic_id = stable_id("Alpha")
    chapters = client.get(f"/comics/{comic_id}").json()["chapters"]
    with_cover = chapters[0]  # "01 - The Journey" has its own cover.jpg

    assert with_cover["coverUrl"].endswith(
        f"/media/{comic_id}/{with_cover['id']}/cover"
    )
    # Two pages, not three: the cover is something to recognise the chapter by,
    # not something to read.
    assert with_cover["pageCount"] == 2


def test_a_chapter_without_a_cover_borrows_the_comics(client):
    comic_id = stable_id("Alpha")
    chapters = client.get(f"/comics/{comic_id}").json()["chapters"]
    without_cover = chapters[1]  # "02" has no cover.jpg

    # The comic's cover, which the app has already loaded for the library card
    # and the chapter screen's header -- free, unlike a full-resolution page.
    assert without_cover["coverUrl"].endswith(f"/media/{comic_id}/cover")


def test_a_chapter_cover_is_served(client):
    comic_id = stable_id("Alpha")
    chapter_id = stable_id("Alpha/01 - The Journey")

    resp = client.get(f"/media/{comic_id}/{chapter_id}/cover")

    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"


def test_a_chapter_without_a_cover_has_none_to_serve(client):
    comic_id = stable_id("Alpha")
    chapter_id = stable_id("Alpha/02")

    resp = client.get(f"/media/{comic_id}/{chapter_id}/cover")

    assert resp.status_code == 404


def test_a_chapter_cover_never_appears_in_the_reading_order(client):
    comic_id = stable_id("Alpha")
    chapter_id = stable_id("Alpha/01 - The Journey")

    pages = client.get(f"/comics/{comic_id}/chapters/{chapter_id}").json()["pages"]

    assert len(pages) == 2
    assert not any(url.endswith("/cover") for url in pages)


def test_get_unknown_comic_returns_404(client):
    resp = client.get("/comics/deadbeefdeadbeef")
    assert resp.status_code == 404


def test_healthz_reports_catalog_size(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["comics"] == 2
    assert body["chapters"] == 3
