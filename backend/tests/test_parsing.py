"""Chapter-name parsing and natural page-sort tests."""

from __future__ import annotations

import pytest

from app.scanner import _natural_key, _parse_chapter_name


@pytest.mark.parametrize(
    "name, expected",
    [
        ("01-bai1", (1, "bai1")),
        ("01", (1, "Chapter 1")),
        ("10 – Later", (10, "Later")),   # en-dash separator
        ("01 - The Journey", (1, "The Journey")),
        ("003_Prologue", (3, "Prologue")),
        ("5.Finale", (5, "Finale")),
    ],
)
def test_parse_chapter_name_valid(name, expected):
    assert _parse_chapter_name(name) == expected


@pytest.mark.parametrize("name", ["weird", "01 empty", "", "chapter one", "-3"])
def test_parse_chapter_name_unparseable(name):
    assert _parse_chapter_name(name) is None


def test_natural_sort_orders_2_before_10():
    names = ["10.jpg", "2.jpg", "1.jpg"]
    assert sorted(names, key=_natural_key) == ["1.jpg", "2.jpg", "10.jpg"]


def test_natural_sort_mixes_padded_and_unpadded():
    names = ["001.jpg", "10.jpg", "2.jpg"]
    assert sorted(names, key=_natural_key) == ["001.jpg", "2.jpg", "10.jpg"]
