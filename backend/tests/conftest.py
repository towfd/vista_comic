"""Shared fixtures for the backend test suite.

Every test builds its own temporary fixture tree under ``tmp_path``; nothing
here reads ``MANGA_LIBRARY_PATH`` or the developer's real library.
"""

from __future__ import annotations

from pathlib import Path

import pytest

_IMG = b"fake-image-bytes"


def _write_page(path: Path, data: bytes = _IMG) -> Path:
    """Create a fake page/cover file (metadata-only; contents are irrelevant)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


@pytest.fixture
def write_page():
    """Return a helper that writes a fake image file at an absolute path."""
    return _write_page


@pytest.fixture
def sample_library(tmp_path, write_page):
    """Build a small, well-formed library and return (root, expectations).

    Layout::

        library/
        ├── Alpha/
        │   ├── cover.png
        │   ├── 01 - The Journey/  (2 pages)
        │   └── 02/                (1 page)
        └── Beta/
            └── 01-intro/          (3 pages, no explicit cover)
    """
    root = tmp_path / "library"

    write_page(root / "Alpha" / "cover.png")
    write_page(root / "Alpha" / "01 - The Journey" / "001.jpg")
    write_page(root / "Alpha" / "01 - The Journey" / "002.jpg")
    write_page(root / "Alpha" / "02" / "001.jpg")

    write_page(root / "Beta" / "01-intro" / "1.jpg")
    write_page(root / "Beta" / "01-intro" / "2.jpg")
    write_page(root / "Beta" / "01-intro" / "10.jpg")

    return root
