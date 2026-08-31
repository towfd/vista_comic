"""The across-days interval table (vocabulary stage 6, ticket 01).

Pure functions over a slot and a moment, so every rule is testable without a
database. What a card *does* between slots lives in `test_scheduler.py`; this
module is only about the table itself.

Rewritten for stage 6. The tests that used to live here — a failure returning to
the bottom from any height, and a card falling and climbing back inside one day —
described `move`, which no longer exists: falling one slot instead of all the way
is the change, and where a card goes next is now the state machine's business.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.ladder import (
    FIRST_SLOT,
    LADDER_INTERVALS,
    TOP_SLOT,
    clamp_slot,
    due_after,
    interval_days,
)

MOMENT = datetime(2026, 8, 31, 21, 15, tzinfo=timezone.utc)


def test_the_intervals_are_the_ones_the_spec_states():
    """Seven slots, not five.

    Pinned as a fact rather than left implicit, because the app shows `n / 7`
    and a silent change here would make that readout lie.
    """
    assert LADDER_INTERVALS == (1, 3, 7, 21, 60, 150, 365)
    assert TOP_SLOT == 6


def test_the_table_keeps_growing_multiplicatively():
    """Each interval is at least twice the one before it.

    The reader proposed 90 and 120 after 60, which are ×1.5 and ×1.33 — the
    curve flattening exactly where a card has proved itself most stable. This
    test is why 150 and 365 were chosen instead, and it fails if anyone puts the
    flatter numbers back.
    """
    for smaller, larger in zip(LADDER_INTERVALS, LADDER_INTERVALS[1:]):
        assert larger >= smaller * 2


@pytest.mark.parametrize("slot", range(len(LADDER_INTERVALS)))
def test_every_slot_is_due_in_the_future(slot):
    assert due_after(slot, MOMENT) > MOMENT


def test_the_due_time_comes_from_the_slot():
    assert due_after(0, MOMENT) == MOMENT + timedelta(days=1)
    assert due_after(TOP_SLOT, MOMENT) == MOMENT + timedelta(days=365)


def test_the_due_time_is_counted_from_the_answer_not_the_last_due_date():
    """A card answered four days late is not owed those four days back.

    The point of reference is when the reader actually recalled it.
    """
    late = MOMENT + timedelta(days=4)
    assert due_after(2, late) == late + timedelta(days=7)


def test_a_slot_past_either_end_is_clamped():
    assert clamp_slot(-3) == FIRST_SLOT
    assert clamp_slot(99) == TOP_SLOT
    assert interval_days(99) == 365
