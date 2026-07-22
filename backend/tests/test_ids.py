"""Stable-ID contract tests.

The hashes below are *load-bearing*: Slice 4 reading-progress persistence keys
on them, so they must never drift. If one of these assertions fails, an ID
scheme change has silently broken saved-progress compatibility.
"""

from __future__ import annotations

import pytest

from app.ids import _ID_LENGTH, stable_id


def test_stable_id_is_deterministic():
    assert stable_id("marrymyhusband") == stable_id("marrymyhusband")


@pytest.mark.parametrize(
    "rel, expected",
    [
        ("marrymyhusband", "3fac76ac49c2a953"),
        ("marrymyhusband/01-bai1", "4995af79721482ab"),
        ("Frieren", "a72c4a6533f35720"),
    ],
)
def test_stable_id_known_vectors(rel, expected):
    # Pinned contract: these exact strings must be reproduced across restarts.
    assert stable_id(rel) == expected


def test_stable_id_length_is_16_hex():
    value = stable_id("Frieren/01 - The Journey")
    assert len(value) == _ID_LENGTH == 16
    int(value, 16)  # raises if it is not valid hex


def test_different_paths_yield_different_ids():
    assert stable_id("Alpha") != stable_id("Beta")
    assert stable_id("Alpha/01") != stable_id("Alpha/02")


def test_multi_segment_equals_joined_path():
    # stable_id joins segments with "/", so it matches the relative POSIX path.
    assert stable_id("Alpha", "01-bai1") == stable_id("Alpha/01-bai1")
