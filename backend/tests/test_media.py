"""Reader endpoint + /media route tests (Slice 2).

Every test builds a self-contained fixture tree under ``tmp_path`` and backs the
app via ``main.load_catalog`` (or, for the traversal cases, by installing a
hand-crafted catalog). Nothing here touches the real ``MANGA_LIBRARY_PATH``.

Page selector scheme under test: ``/media/{comicId}/{chapterId}/{page}`` uses a
1-based page index into the chapter's ordered pages, matching the reader
endpoint's ``pages`` array 1:1.
"""

from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from app import main
from app.ids import stable_id
from app.models import ChapterEntry, ComicEntry
from app.scanner import Catalog, ScanReport

BASE = "http://testserver"


@pytest.fixture
def client(sample_library, progress_db):
    catalog = main.load_catalog(sample_library)
    assert catalog.comics, "fixture catalog should not be empty"
    return TestClient(main.app)


@pytest.fixture
def mixed_library(tmp_path, write_page):
    """A comic whose one chapter mixes jpg/png/webp with distinct byte contents.

    Layout::

        library/Mixed/01/{001.jpg, 002.png, 003.webp}
    """
    root = tmp_path / "library"
    write_page(root / "Mixed" / "01" / "001.jpg", b"jpg-bytes-1")
    write_page(root / "Mixed" / "01" / "002.png", b"png-bytes-2")
    write_page(root / "Mixed" / "01" / "003.webp", b"webp-bytes-3")
    return root


@pytest.fixture
def mixed_client(mixed_library):
    main.load_catalog(mixed_library)
    return TestClient(main.app)


# --------------------------------------------------------------------------- #
# Reader endpoint: GET /comics/{comicId}/chapters/{chapterId}
# --------------------------------------------------------------------------- #


def test_chapter_pages_ordered_absolute_urls(client):
    comic_id = stable_id("Beta")
    chapter_id = stable_id("Beta/01-intro")
    resp = client.get(f"/comics/{comic_id}/chapters/{chapter_id}")
    assert resp.status_code == 200

    body = resp.json()
    assert set(body) == {"id", "number", "title", "pages"}
    assert body["id"] == chapter_id
    assert body["number"] == 1
    # 01-intro holds 1.jpg, 2.jpg, 10.jpg -> natural order 1,2,10 -> 3 pages.
    assert len(body["pages"]) == 3
    # Pages are absolute, 1-based, and in order.
    assert body["pages"] == [
        f"{BASE}/media/{comic_id}/{chapter_id}/1",
        f"{BASE}/media/{comic_id}/{chapter_id}/2",
        f"{BASE}/media/{comic_id}/{chapter_id}/3",
    ]


def test_chapter_page_count_matches_detail(client):
    comic_id = stable_id("Alpha")
    detail = client.get(f"/comics/{comic_id}").json()
    for ch in detail["chapters"]:
        pages = client.get(f"/comics/{comic_id}/chapters/{ch['id']}").json()["pages"]
        assert len(pages) == ch["pageCount"]


def test_chapter_unknown_comic_404(client):
    chapter_id = stable_id("Beta/01-intro")
    resp = client.get(f"/comics/deadbeefdeadbeef/chapters/{chapter_id}")
    assert resp.status_code == 404


def test_chapter_unknown_chapter_404(client):
    comic_id = stable_id("Alpha")
    resp = client.get(f"/comics/{comic_id}/chapters/deadbeefdeadbeef")
    assert resp.status_code == 404


def test_chapter_belonging_to_other_comic_404(client):
    # A real chapter id, but requested under a different (real) comic.
    alpha_id = stable_id("Alpha")
    beta_chapter_id = stable_id("Beta/01-intro")
    resp = client.get(f"/comics/{alpha_id}/chapters/{beta_chapter_id}")
    assert resp.status_code == 404


# --------------------------------------------------------------------------- #
# Media route: GET /media/{comicId}/{chapterId}/{page}
# --------------------------------------------------------------------------- #


def test_media_page_content_types(mixed_client):
    comic_id = stable_id("Mixed")
    chapter_id = stable_id("Mixed/01")
    cases = [
        (1, "image/jpeg", b"jpg-bytes-1"),
        (2, "image/png", b"png-bytes-2"),
        (3, "image/webp", b"webp-bytes-3"),
    ]
    for index, content_type, expected_bytes in cases:
        resp = mixed_client.get(f"/media/{comic_id}/{chapter_id}/{index}")
        assert resp.status_code == 200
        assert resp.headers["content-type"] == content_type
        assert resp.content == expected_bytes


def test_media_page_by_index_order(mixed_client):
    """Page N returns the Nth file in reading order."""
    comic_id = stable_id("Mixed")
    chapter_id = stable_id("Mixed/01")
    assert mixed_client.get(f"/media/{comic_id}/{chapter_id}/1").content == b"jpg-bytes-1"
    assert mixed_client.get(f"/media/{comic_id}/{chapter_id}/3").content == b"webp-bytes-3"


def test_media_out_of_range_page_404(mixed_client):
    comic_id = stable_id("Mixed")
    chapter_id = stable_id("Mixed/01")
    assert mixed_client.get(f"/media/{comic_id}/{chapter_id}/0").status_code == 404
    assert mixed_client.get(f"/media/{comic_id}/{chapter_id}/4").status_code == 404


def test_media_non_integer_page_404(mixed_client):
    comic_id = stable_id("Mixed")
    chapter_id = stable_id("Mixed/01")
    assert mixed_client.get(f"/media/{comic_id}/{chapter_id}/001.jpg").status_code == 404


def test_media_unknown_ids_404(mixed_client):
    comic_id = stable_id("Mixed")
    chapter_id = stable_id("Mixed/01")
    assert mixed_client.get(f"/media/deadbeef/{chapter_id}/1").status_code == 404
    assert mixed_client.get(f"/media/{comic_id}/deadbeef/1").status_code == 404


# --------------------------------------------------------------------------- #
# Cover route: GET /media/{comicId}/cover
# --------------------------------------------------------------------------- #


def test_cover_explicit_file(client):
    """Alpha has an explicit cover.png."""
    comic_id = stable_id("Alpha")
    resp = client.get(f"/media/{comic_id}/cover")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"


def test_cover_fallback_first_page(client):
    """Beta has no cover.*; falls back to the first page (1.jpg) of chapter 1."""
    comic_id = stable_id("Beta")
    resp = client.get(f"/media/{comic_id}/cover")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"


def test_cover_unknown_comic_404(client):
    assert client.get("/media/deadbeefdeadbeef/cover").status_code == 404


# --------------------------------------------------------------------------- #
# Path-traversal / symlink escape: the media route must never serve a file
# outside the resolved library root, even if a stored path points there.
# --------------------------------------------------------------------------- #


def _install_catalog_with_paths(root, page_rel, cover_rel):
    """Hand-build a catalog with crafted relative paths and install it globally."""
    comic_id = stable_id("Evil")
    chapter_id = stable_id("Evil/01")
    chapter = ChapterEntry(id=chapter_id, number=1, title="x", page_paths=[page_rel])
    comic = ComicEntry(id=comic_id, title="Evil", cover_path=cover_rel, chapters=[chapter])
    main.state.catalog = Catalog.build([comic], ScanReport(), root)
    return comic_id, chapter_id


def test_media_rejects_dotdot_traversal(tmp_path, write_page):
    """A stored ``..`` path that escapes the root is rejected, never served."""
    root = tmp_path / "library"
    root.mkdir(parents=True)
    # A real secret file sitting outside the library root.
    write_page(tmp_path / "secret.jpg", b"top-secret")

    comic_id, chapter_id = _install_catalog_with_paths(
        root, page_rel="../secret.jpg", cover_rel="../secret.jpg"
    )
    client = TestClient(main.app)
    assert client.get(f"/media/{comic_id}/{chapter_id}/1").status_code == 404
    assert client.get(f"/media/{comic_id}/cover").status_code == 404


def test_media_rejects_symlink_escape(tmp_path, write_page):
    """A page/cover that is a symlink resolving outside the root is rejected."""
    root = tmp_path / "library"
    (root / "Evil" / "01").mkdir(parents=True)
    secret = write_page(tmp_path / "secret.jpg", b"top-secret")
    # A symlink inside the library pointing at the outside secret.
    link = root / "Evil" / "01" / "link.jpg"
    link.symlink_to(secret)

    comic_id, chapter_id = _install_catalog_with_paths(
        root, page_rel="Evil/01/link.jpg", cover_rel="Evil/01/link.jpg"
    )
    client = TestClient(main.app)
    assert client.get(f"/media/{comic_id}/{chapter_id}/1").status_code == 404
    assert client.get(f"/media/{comic_id}/cover").status_code == 404


# --------------------------------------------------------------------------- #
# Caching: every image says ``no-cache`` and carries an ETag built from the
# file's path, so a browser checks before reusing one and a page whose file was
# renamed is fetched again (see ``main._image_response``).
# --------------------------------------------------------------------------- #


@pytest.fixture
def covered_client(tmp_path, write_page):
    """One comic with its own cover, one chapter with a page and its own cover."""
    root = tmp_path / "library"
    write_page(root / "Covered" / "cover.png", b"comic-cover")
    write_page(root / "Covered" / "01" / "001.jpg", b"page-one")
    write_page(root / "Covered" / "01" / "cover.jpg", b"chapter-cover")
    main.load_catalog(root)
    return TestClient(main.app)


_COVERED_URLS = {
    "page": f"/media/{stable_id('Covered')}/{stable_id('Covered/01')}/1",
    "comic cover": f"/media/{stable_id('Covered')}/cover",
    "chapter cover": f"/media/{stable_id('Covered')}/{stable_id('Covered/01')}/cover",
}
_COVERED_BYTES = {
    "page": b"page-one",
    "comic cover": b"comic-cover",
    "chapter cover": b"chapter-cover",
}


@pytest.mark.parametrize("kind", list(_COVERED_URLS))
def test_image_must_be_checked_before_reuse(covered_client, kind):
    resp = covered_client.get(_COVERED_URLS[kind])
    assert resp.status_code == 200
    assert resp.content == _COVERED_BYTES[kind]
    assert resp.headers["cache-control"] == "no-cache"
    etag = resp.headers["etag"]
    assert etag.startswith('"') and etag.endswith('"') and len(etag) > 2


@pytest.mark.parametrize("kind", list(_COVERED_URLS))
def test_unchanged_image_answers_304_without_body(covered_client, kind):
    etag = covered_client.get(_COVERED_URLS[kind]).headers["etag"]

    resp = covered_client.get(_COVERED_URLS[kind], headers={"If-None-Match": etag})

    assert resp.status_code == 304
    assert resp.content == b""
    # A 304 repeats the validators, so the browser keeps checking next time.
    assert resp.headers["etag"] == etag
    assert resp.headers["cache-control"] == "no-cache"


def test_other_etag_gets_the_image(covered_client):
    resp = covered_client.get(_COVERED_URLS["page"], headers={"If-None-Match": '"something-else"'})
    assert resp.status_code == 200
    assert resp.content == b"page-one"


@pytest.mark.parametrize(
    "header",
    ["W/{etag}", '"something-else", {etag}', "*"],
    ids=["weak", "in a list", "any"],
)
def test_etag_match_accepts_weak_and_listed_forms(covered_client, header):
    """nginx or Cloudflare may hand the tag back weak (``W/``) or in a list."""
    etag = covered_client.get(_COVERED_URLS["page"]).headers["etag"]
    resp = covered_client.get(_COVERED_URLS["page"], headers={"If-None-Match": header.format(etag=etag)})
    assert resp.status_code == 304


def test_renamed_page_is_fetched_again(tmp_path, write_page):
    """The bug this guards: after renaming a chapter's files, the same page URL
    points at a different file, and the browser kept showing the old image.

    The two files have the same size and modification time -- all that
    Starlette's own ETag is built from -- so only the path tells them apart.
    """
    root = tmp_path / "library"
    first = write_page(root / "Renamed" / "01" / "001.jpg", b"image-A")
    second = write_page(root / "Renamed" / "01" / "002.jpg", b"image-B")
    same_time = 1_700_000_000_000_000_000
    for path in (first, second):
        os.utime(path, ns=(same_time, same_time))
    main.load_catalog(root)
    client = TestClient(main.app)
    url = f"/media/{stable_id('Renamed')}/{stable_id('Renamed/01')}/2"

    before = client.get(url)
    assert before.content == b"image-B"

    # 001 -> 003: page 2 is now image-A (renaming keeps the modification time).
    first.rename(root / "Renamed" / "01" / "003.jpg")
    main.load_catalog(root)

    after = client.get(url, headers={"If-None-Match": before.headers["etag"]})
    assert after.status_code == 200
    assert after.content == b"image-A"
    assert after.headers["etag"] != before.headers["etag"]


def test_edited_page_is_fetched_again(mixed_library, write_page):
    """Same file name, new content: the ETag changes with the size and time."""
    main.load_catalog(mixed_library)
    client = TestClient(main.app)
    url = f"/media/{stable_id('Mixed')}/{stable_id('Mixed/01')}/1"
    etag = client.get(url).headers["etag"]

    write_page(mixed_library / "Mixed" / "01" / "001.jpg", b"jpg-bytes-1, redrawn")

    resp = client.get(url, headers={"If-None-Match": etag})
    assert resp.status_code == 200
    assert resp.content == b"jpg-bytes-1, redrawn"
