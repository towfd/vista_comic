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
