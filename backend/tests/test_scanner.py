"""End-to-end scanner tests over temporary fixture trees.

Covers cover resolution, natural ordering, skip-and-report behaviour, and the
symlink / path-traversal guard (Fix 1). All trees are built under ``tmp_path``.
"""

from __future__ import annotations

from app.scanner import scan_library


def test_well_formed_library_scans(sample_library):
    catalog = scan_library(sample_library)

    titles = [c.title for c in catalog.comics]
    assert titles == ["Alpha", "Beta"]  # comics in natural order

    alpha = catalog.comics[0]
    assert [ch.number for ch in alpha.chapters] == [1, 2]
    assert alpha.chapters[0].title == "The Journey"
    assert alpha.chapters[1].title == "Chapter 2"  # bare "02" -> fallback title
    assert alpha.chapters[0].page_count == 2

    assert catalog.report.skipped_comics == []
    assert catalog.report.skipped_chapters == []
    assert catalog.report.escaped_entries == []


def test_explicit_cover_is_chosen(sample_library):
    catalog = scan_library(sample_library)
    alpha = catalog.comics[0]
    assert alpha.cover_path == "Alpha/cover.png"


def test_cover_falls_back_to_first_page_of_lowest_chapter(sample_library):
    catalog = scan_library(sample_library)
    beta = catalog.comics[1]  # no cover.* -> first natural page of chapter 1
    assert beta.cover_path == "Beta/01-intro/1.jpg"


def test_pages_are_natural_sorted(sample_library):
    catalog = scan_library(sample_library)
    beta = catalog.comics[1]
    assert beta.chapters[0].page_paths == [
        "Beta/01-intro/1.jpg",
        "Beta/01-intro/2.jpg",
        "Beta/01-intro/10.jpg",
    ]


def test_empty_chapter_is_skipped_and_reported(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Comic" / "01" / "001.jpg")
    (root / "Comic" / "02").mkdir(parents=True)  # empty chapter dir

    catalog = scan_library(root)

    comic = catalog.comics[0]
    assert [ch.number for ch in comic.chapters] == [1]
    assert any("02 (no valid pages)" in s for s in catalog.report.skipped_chapters)


def test_empty_comic_is_skipped_and_reported(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Good" / "01" / "001.jpg")
    (root / "Empty" / "01").mkdir(parents=True)  # chapter with no pages

    catalog = scan_library(root)

    assert [c.title for c in catalog.comics] == ["Good"]
    assert any("Empty (no valid chapters)" in s for s in catalog.report.skipped_comics)


def test_unparseable_chapter_name_is_skipped_and_reported(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Comic" / "01" / "001.jpg")
    write_page(root / "Comic" / "weird" / "001.jpg")

    catalog = scan_library(root)

    assert [ch.number for ch in catalog.comics[0].chapters] == [1]
    assert any("weird (unparseable name)" in s for s in catalog.report.skipped_chapters)


def test_unsupported_and_hidden_files_are_skipped(tmp_path, write_page):
    root = tmp_path / "library"
    ch = root / "Comic" / "01"
    write_page(ch / "001.jpg")
    write_page(ch / "notes.txt")       # unsupported extension -> counted
    write_page(ch / "readme.md")       # unsupported extension -> counted
    write_page(ch / ".DS_Store")       # hidden -> ignored, not counted
    write_page(ch / ".hidden.jpg")     # hidden dotfile -> ignored, not counted

    catalog = scan_library(root)

    assert catalog.comics[0].chapters[0].page_paths == ["Comic/01/001.jpg"]
    assert catalog.report.skipped_files == 2  # only the two unsupported types


def test_hidden_directories_are_ignored(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Comic" / "01" / "001.jpg")
    write_page(root / ".git" / "01" / "001.jpg")          # hidden comic dir
    write_page(root / "Comic" / ".cache" / "001.jpg")     # hidden chapter dir

    catalog = scan_library(root)

    assert [c.title for c in catalog.comics] == ["Comic"]
    assert [ch.number for ch in catalog.comics[0].chapters] == [1]


# --- Fix 1: symlink escape / path-traversal guard --------------------------


def test_symlinked_comic_escaping_root_is_skipped(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Real" / "01" / "001.jpg")

    outside = tmp_path / "outside"
    write_page(outside / "01" / "secret.jpg")
    (root / "Escape").symlink_to(outside, target_is_directory=True)

    catalog = scan_library(root)

    assert [c.title for c in catalog.comics] == ["Real"]
    assert any("Escape" in s for s in catalog.report.escaped_entries)


def test_symlinked_chapter_escaping_root_is_skipped(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Comic" / "01" / "001.jpg")

    outside_chapter = tmp_path / "outside" / "02"
    write_page(outside_chapter / "secret.jpg")
    (root / "Comic" / "02").symlink_to(outside_chapter, target_is_directory=True)

    catalog = scan_library(root)

    comic = catalog.comics[0]
    assert [ch.number for ch in comic.chapters] == [1]
    assert not any(p.startswith("Comic/02") for ch in comic.chapters for p in ch.page_paths)
    assert any("Comic/02" in s for s in catalog.report.escaped_entries)


def test_symlinked_page_escaping_root_is_skipped(tmp_path, write_page):
    root = tmp_path / "library"
    ch = root / "Comic" / "01"
    write_page(ch / "001.jpg")

    outside_file = tmp_path / "outside" / "secret.jpg"
    write_page(outside_file)
    (ch / "002.jpg").symlink_to(outside_file)

    catalog = scan_library(root)

    pages = catalog.comics[0].chapters[0].page_paths
    assert pages == ["Comic/01/001.jpg"]
    assert any("Comic/01/002.jpg" in s for s in catalog.report.escaped_entries)


def test_symlink_cycle_to_ancestor_is_skipped(tmp_path, write_page):
    """A chapter symlinked back to its own comic must not be followed."""
    root = tmp_path / "library"
    comic = root / "Comic"
    write_page(comic / "01" / "001.jpg")
    # Valid chapter name, but the target is the comic itself (a cycle).
    (comic / "99").symlink_to(comic, target_is_directory=True)

    catalog = scan_library(root)

    assert [ch.number for ch in catalog.comics[0].chapters] == [1]
    assert any("Comic/99" in s for s in catalog.report.escaped_entries)


def test_scan_is_idempotent(sample_library):
    first = scan_library(sample_library)
    second = scan_library(sample_library)

    def snapshot(cat):
        return [
            (c.id, c.title, c.cover_path,
             [(ch.id, ch.number, ch.title, tuple(ch.page_paths)) for ch in c.chapters])
            for c in cat.comics
        ]

    assert snapshot(first) == snapshot(second)


def test_decimal_chapter_numbers_keep_their_decimal_part(tmp_path, write_page):
    # Split chapters like 01 / 01.5 / 07.1 / 07.2 are distinct chapters: the web
    # reader finds a chapter's OCR and translation files by this number, so
    # truncating 01.5 to 1 shows chapter 1's translations on chapter 1.5.
    root = tmp_path / "library"
    for name in ["08", "07.2", "01.5", "02", "07.1", "01"]:
        write_page(root / "Comic" / name / "001.jpg")

    chapters = scan_library(root).comics[0].chapters

    assert [ch.number for ch in chapters] == [1, 1.5, 2, 7.1, 7.2, 8]
    assert [ch.title for ch in chapters] == [
        "Chapter 1", "Chapter 1.5", "Chapter 2", "Chapter 7.1", "Chapter 7.2", "Chapter 8",
    ]
    # Whole numbers stay integers, so the API keeps sending 8 and not 8.0.
    assert all(type(ch.number) is int for ch in chapters if ch.number == int(ch.number))


def test_decimal_chapter_number_with_a_title(tmp_path, write_page):
    root = tmp_path / "library"
    write_page(root / "Comic" / "01.5 - Side Story" / "001.jpg")
    write_page(root / "Comic" / "12.Finale" / "001.jpg")

    chapters = scan_library(root).comics[0].chapters

    assert [(ch.number, ch.title) for ch in chapters] == [(1.5, "Side Story"), (12, "Finale")]


# ---------------------------------------------------------------------------
# Display title from an optional <comic>/title.txt.
# ---------------------------------------------------------------------------


def _comic_with_title_file(tmp_path, write_page, data):
    root = tmp_path / "library"
    write_page(root / "lam_nong_dan" / "01" / "001.jpg")
    if data is not None:
        (root / "lam_nong_dan" / "title.txt").write_bytes(data)
    return root


def test_display_title_is_read_from_title_txt(tmp_path, write_page):
    root = _comic_with_title_file(
        tmp_path, write_page, "Làm Nông Dân Trong Tòa Tháp Thử Thách\n".encode("utf-8")
    )
    comic = scan_library(root).comics[0]
    assert comic.display_title == "Làm Nông Dân Trong Tòa Tháp Thử Thách"
    assert comic.title == "lam_nong_dan"  # the folder name is untouched


def test_display_title_is_none_without_title_txt(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, None)
    assert scan_library(root).comics[0].display_title is None


def test_display_title_is_none_for_a_blank_file(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, b"  \n\t\n\r\n")
    assert scan_library(root).comics[0].display_title is None


def test_display_title_is_none_for_an_empty_file(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, b"")
    assert scan_library(root).comics[0].display_title is None


def test_display_title_is_trimmed(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, b"  \tSket Dance  \r\n")
    assert scan_library(root).comics[0].display_title == "Sket Dance"


def test_display_title_takes_the_first_non_blank_line(tmp_path, write_page):
    root = _comic_with_title_file(
        tmp_path, write_page, "\n   \nThám Tử Conan\nDetective Conan\n".encode("utf-8")
    )
    assert scan_library(root).comics[0].display_title == "Thám Tử Conan"


def test_display_title_ignores_a_utf8_bom(tmp_path, write_page):
    root = _comic_with_title_file(
        tmp_path, write_page, "﻿Sousou no Frieren".encode("utf-8")
    )
    assert scan_library(root).comics[0].display_title == "Sousou no Frieren"


def test_display_title_is_none_for_non_utf8_bytes(tmp_path, write_page):
    # Latin-1 bytes, not valid UTF-8: dropped rather than shown as mojibake.
    root = _comic_with_title_file(tmp_path, write_page, b"Th\xe1m T\xf6 Conan\n")
    comic = scan_library(root).comics[0]
    assert comic.display_title is None
    assert [ch.number for ch in comic.chapters] == [1]  # comic still scanned


def test_display_title_ignores_a_directory_named_title_txt(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, None)
    (root / "lam_nong_dan" / "title.txt").mkdir()
    comic = scan_library(root).comics[0]
    assert comic.display_title is None
    assert [ch.number for ch in comic.chapters] == [1]


def test_display_title_symlink_escaping_root_is_ignored(tmp_path, write_page):
    outside = tmp_path / "outside.txt"
    outside.write_text("Leaked", encoding="utf-8")
    root = _comic_with_title_file(tmp_path, write_page, None)
    (root / "lam_nong_dan" / "title.txt").symlink_to(outside)
    assert scan_library(root).comics[0].display_title is None


def test_title_txt_does_not_affect_chapters_cover_or_ids(tmp_path, write_page):
    without = tmp_path / "a"
    with_title = tmp_path / "b"
    for root in (without, with_title):
        write_page(root / "Comic" / "01" / "001.jpg")
        write_page(root / "Comic" / "02" / "001.jpg")
    (with_title / "Comic" / "title.txt").write_text("Comic Title\n", encoding="utf-8")

    plain = scan_library(without)
    titled = scan_library(with_title)

    a, b = plain.comics[0], titled.comics[0]
    assert b.display_title == "Comic Title"
    assert a.id == b.id
    assert [ch.id for ch in a.chapters] == [ch.id for ch in b.chapters]
    assert [ch.number for ch in b.chapters] == [1, 2]
    assert b.cover_path == "Comic/01/001.jpg"  # first page, not title.txt
    assert all("title.txt" not in p for ch in b.chapters for p in ch.page_paths)
    assert titled.report.skipped_chapters == []
    assert titled.report.skipped_files == plain.report.skipped_files


def test_rescan_picks_up_a_changed_title_txt(tmp_path, write_page):
    root = _comic_with_title_file(tmp_path, write_page, b"Old Title")
    assert scan_library(root).comics[0].display_title == "Old Title"
    (root / "lam_nong_dan" / "title.txt").write_bytes(b"New Title")
    assert scan_library(root).comics[0].display_title == "New Title"
