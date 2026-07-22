"""Read-only scan of the manga library into an in-memory catalog.

Hard constraint: this module NEVER writes, renames, or deletes anything under
the library root. It only lists directories and reads file metadata.

Folder format (from docs/backend-architecture.md):

    library / comic / chapter / page-image

- Comic title  = comic directory name.
- Chapter name = ``^\\s*(\\d+)\\s*(?:[-_.–]\\s*(.*))?$`` -> leading int is
  ``number``; remainder (if any) is ``title``; else ``"Chapter <number>"``.
- Pages        = image files with accepted extensions, natural-sorted.
- Cover        = ``cover.*`` at the comic root, else the first page of the
  lowest-numbered chapter.
- Hidden files (``.DS_Store`` / dotfiles) and unsupported types are skipped.
- Comics / chapters with no valid pages are skipped and reported, never crash.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ``Path.is_relative_to`` requires Python 3.9+ (we target 3.12).

from .ids import stable_id
from .models import ChapterEntry, ComicEntry

logger = logging.getLogger("vista_comic.scanner")

# Accepted page extensions (lowercased, with leading dot).
PAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

# Chapter directory name -> (number, optional title). Separators: - _ . and en-dash.
_CHAPTER_RE = re.compile(r"^\s*(\d+)\s*(?:[-–_.]\s*(.*))?$")

_NUM_SPLIT_RE = re.compile(r"(\d+)")


def _natural_key(name: str) -> List[object]:
    """Sort key giving natural order (``2`` before ``10``), case-insensitive."""
    parts = _NUM_SPLIT_RE.split(name)
    key: List[object] = []
    for i, part in enumerate(parts):
        if i % 2 == 1:  # numeric chunk
            key.append((1, int(part)))
        elif part:
            key.append((0, part.lower()))
    return key


def _is_hidden(entry: Path) -> bool:
    return entry.name.startswith(".")


def _is_page(entry: Path) -> bool:
    return (
        entry.is_file()
        and not _is_hidden(entry)
        and entry.suffix.lower() in PAGE_EXTENSIONS
    )


def _real_within(entry: Path, root_real: Path) -> Optional[Path]:
    """Resolve ``entry`` and return its real path only if it stays under root.

    Symlinks are followed by ``resolve()``; if the real target escapes the
    library root we return ``None`` so the caller can skip-and-report it.
    Slice 2's ``/media`` route resolves the stored relative paths and joins
    them onto the root, so a stored escaping path would read files outside the
    library -- hence the guard lives here at scan time. Read-only throughout.
    """
    try:
        real = entry.resolve()
    except OSError:
        return None
    return real if real.is_relative_to(root_real) else None


def _safe_child_dir(entry: Path, root_real: Path, parent_real: Path) -> Optional[Path]:
    """Real path of a directory entry, or ``None`` if unsafe to descend into.

    Rejects (a) a symlink whose target escapes the library root, and (b) a
    symlink pointing at an ancestor or at the parent itself, which would form a
    cycle and, under a recursive walk, cause unbounded recursion.
    """
    real = _real_within(entry, root_real)
    if real is None:
        return None
    # A symlink to root / an ancestor of the parent / the parent itself would
    # make ``parent_real`` sit under ``real`` -- reject to avoid a cycle.
    if parent_real == real or parent_real.is_relative_to(real):
        return None
    return real


@dataclass
class ScanReport:
    """Non-fatal issues surfaced during a scan, for observability."""

    skipped_comics: List[str] = field(default_factory=list)
    skipped_chapters: List[str] = field(default_factory=list)
    skipped_files: int = 0
    # Entries whose real (symlink-resolved) path escaped the library root, or
    # formed a cycle back to an ancestor. Reported for observability; never
    # followed into stored paths.
    escaped_entries: List[str] = field(default_factory=list)


@dataclass
class Catalog:
    """The in-memory catalog produced by one scan."""

    comics: List[ComicEntry]
    by_id: Dict[str, ComicEntry]
    report: ScanReport

    @classmethod
    def build(cls, comics: List[ComicEntry], report: ScanReport) -> "Catalog":
        return cls(comics=comics, by_id={c.id: c for c in comics}, report=report)


def _parse_chapter_name(name: str) -> Optional[Tuple[int, str]]:
    """Return (number, title) or None if the name is not a chapter."""
    m = _CHAPTER_RE.match(name)
    if not m:
        return None
    number = int(m.group(1))
    remainder = (m.group(2) or "").strip()
    title = remainder if remainder else f"Chapter {number}"
    return number, title


def _list_pages(
    chapter_dir: Path, root: Path, root_real: Path, report: ScanReport
) -> List[Path]:
    chapter_rel = chapter_dir.relative_to(root).as_posix()
    pages: List[Path] = []
    for entry in chapter_dir.iterdir():
        if entry.is_dir():
            continue
        if _is_page(entry):
            # A page file that is a symlink out of the library is not served.
            if _real_within(entry, root_real) is None:
                report.escaped_entries.append(
                    f"{chapter_rel}/{entry.name} (page escapes root)"
                )
                continue
            pages.append(entry)
        elif not _is_hidden(entry):
            report.skipped_files += 1
    pages.sort(key=lambda p: _natural_key(p.name))
    return pages


def _scan_comic(
    comic_dir: Path, root: Path, root_real: Path, report: ScanReport
) -> Optional[ComicEntry]:
    comic_rel = comic_dir.relative_to(root).as_posix()
    comic_id = stable_id(comic_rel)

    comic_real = comic_dir.resolve()

    # Collect chapter directories (sorted by parsed number, then natural name).
    parsed: List[Tuple[int, str, Path]] = []
    for entry in comic_dir.iterdir():
        if not entry.is_dir() or _is_hidden(entry):
            continue
        if _safe_child_dir(entry, root_real, comic_real) is None:
            report.escaped_entries.append(
                f"{comic_rel}/{entry.name} (chapter escapes root)"
            )
            continue
        result = _parse_chapter_name(entry.name)
        if result is None:
            report.skipped_chapters.append(f"{comic_rel}/{entry.name} (unparseable name)")
            continue
        number, title = result
        parsed.append((number, title, entry))

    parsed.sort(key=lambda t: (t[0], _natural_key(t[2].name)))

    chapters: List[ChapterEntry] = []
    for number, title, chapter_dir in parsed:
        pages = _list_pages(chapter_dir, root, root_real, report)
        if not pages:
            report.skipped_chapters.append(
                f"{comic_rel}/{chapter_dir.name} (no valid pages)"
            )
            continue
        chapter_id = stable_id(chapter_dir.relative_to(root).as_posix())
        page_paths = [p.relative_to(root).as_posix() for p in pages]
        chapters.append(
            ChapterEntry(
                id=chapter_id,
                number=number,
                title=title,
                page_paths=page_paths,
            )
        )

    if not chapters:
        report.skipped_comics.append(f"{comic_rel} (no valid chapters)")
        return None

    cover_path = _resolve_cover(comic_dir, root, root_real, chapters)
    return ComicEntry(id=comic_id, title=comic_dir.name, cover_path=cover_path, chapters=chapters)


def _resolve_cover(
    comic_dir: Path, root: Path, root_real: Path, chapters: List[ChapterEntry]
) -> Optional[str]:
    """cover.* at the comic root, else first page of the lowest-numbered chapter."""
    covers = [
        e
        for e in comic_dir.iterdir()
        if _is_page(e)
        and e.stem.lower() == "cover"
        and _real_within(e, root_real) is not None
    ]
    if covers:
        covers.sort(key=lambda p: _natural_key(p.name))
        return covers[0].relative_to(root).as_posix()

    # Chapters are already ordered by number; first page of the first chapter.
    if chapters and chapters[0].page_paths:
        return chapters[0].page_paths[0]
    return None


def scan_library(root: Path) -> Catalog:
    """Walk ``root`` read-only and return the in-memory catalog.

    Comics are ordered by natural name for a stable, deterministic response.
    """
    report = ScanReport()
    comics: List[ComicEntry] = []

    root_real = root.resolve()

    comic_dirs: List[Path] = []
    for e in root.iterdir():
        if not e.is_dir() or _is_hidden(e):
            continue
        if _safe_child_dir(e, root_real, root_real) is None:
            report.escaped_entries.append(f"{e.name} (comic escapes root)")
            continue
        comic_dirs.append(e)
    comic_dirs.sort(key=lambda p: _natural_key(p.name))

    for comic_dir in comic_dirs:
        entry = _scan_comic(comic_dir, root, root_real, report)
        if entry is not None:
            comics.append(entry)

    logger.info(
        "Scan complete: %d comics, %d chapters, %d skipped comics, "
        "%d skipped chapters, %d skipped files, %d escaped entries",
        len(comics),
        sum(c.chapter_count for c in comics),
        len(report.skipped_comics),
        len(report.skipped_chapters),
        report.skipped_files,
        len(report.escaped_entries),
    )
    if report.skipped_comics:
        logger.warning("Skipped comics: %s", report.skipped_comics)
    if report.skipped_chapters:
        logger.warning("Skipped chapters: %s", report.skipped_chapters)
    if report.escaped_entries:
        logger.warning("Skipped escaping symlinks: %s", report.escaped_entries)

    return Catalog.build(comics, report)
