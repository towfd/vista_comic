"""The across-days schedule (vocabulary stage 4, ticket 03).

Pure functions over a rung and a date, so every rule is testable without a
database.

Two of these encode decisions that will feel wrong in the moment and are right
over weeks — `test_a_failure_returns_to_the_bottom_from_any_height` and
`test_wrong_then_passed_on_the_same_day_leaves_the_rung_dropped`. Both have
comments saying why, because both are the kind of thing a future reader would
"fix".
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest

from app.ladder import (
    FIRST_RUNG,
    LADDER_INTERVALS,
    TOP_RUNG,
    move,
    next_due,
    rung_after_failure,
    rung_after_pass,
)

TODAY = date(2026, 8, 20)


# --- climbing ----------------------------------------------------------------


def test_passing_advances_one_rung():
    assert rung_after_pass(0) == 1
    assert rung_after_pass(3) == TOP_RUNG


def test_the_top_rung_clamps_rather_than_overflowing():
    """Sixty days is the longest interval there is. Running off the end would
    index past the table, and there is nothing beyond it to schedule."""
    assert rung_after_pass(TOP_RUNG) == TOP_RUNG


def test_the_due_date_comes_from_the_rung_reached():
    assert next_due(0, today=TODAY) == TODAY + timedelta(days=1)
    assert next_due(TOP_RUNG, today=TODAY) == TODAY + timedelta(days=60)


def test_the_due_date_is_counted_from_today_not_from_the_last_one():
    """A card answered four days late is not owed those four days back.

    What matters is when the reader actually recalled it, not when a schedule
    had hoped they would.
    """
    late = TODAY + timedelta(days=4)

    assert next_due(1, today=late) == late + timedelta(days=3)


# --- falling -----------------------------------------------------------------


def test_a_failure_returns_to_the_bottom_from_any_height():
    """**Not one rung down.**

    A card forgotten at sixty days would then be next asked in twenty-one — a
    long wait after just proving it is gone. An interval is supposed to reflect
    what the reader retains, and a word they have just missed retains nothing
    worth scheduling far out.
    """
    assert rung_after_failure(TOP_RUNG) == FIRST_RUNG
    assert rung_after_failure(3) == FIRST_RUNG
    assert rung_after_failure(0) == FIRST_RUNG


def test_a_failed_card_is_due_tomorrow():
    result = move(rung=TOP_RUNG, last_move_on=None, today=TODAY, passed=False)

    assert result == (FIRST_RUNG, TODAY + timedelta(days=1))


# --- once a day --------------------------------------------------------------


def test_the_first_resolution_of_the_day_is_the_only_one():
    already = move(rung=2, last_move_on=TODAY, today=TODAY, passed=True)

    assert already is None


def test_wrong_then_passed_on_the_same_day_leaves_the_rung_dropped():
    """The case that will feel unfair, and is deliberate.

    The reader *did* end the session knowing the word — but the gap already
    happened: they met it today and did not have it. Letting an afternoon of
    drilling erase that would make the ladder a record of effort rather than of
    memory, and the interval it schedules would stop meaning anything. Passing
    it later still counts for the *day*; it does not count here.
    """
    dropped = move(rung=3, last_move_on=None, today=TODAY, passed=False)
    assert dropped == (FIRST_RUNG, TODAY + timedelta(days=1))

    # …and the same card reaching 通過 an hour later moves nothing.
    assert move(rung=FIRST_RUNG, last_move_on=TODAY, today=TODAY, passed=True) is None


def test_passed_then_wrong_on_the_same_day_leaves_the_rung_advanced():
    """The mirror image, and it follows from the same rule rather than from a
    second one: whichever resolution came first is the day's move."""
    advanced = move(rung=1, last_move_on=None, today=TODAY, passed=True)
    assert advanced == (2, TODAY + timedelta(days=7))

    assert move(rung=2, last_move_on=TODAY, today=TODAY, passed=False) is None


def test_a_new_day_moves_again():
    tomorrow = TODAY + timedelta(days=1)

    assert move(rung=1, last_move_on=TODAY, today=tomorrow, passed=True) is not None


def test_a_gap_of_weeks_is_not_a_backlog():
    """Nothing accrues while the reader is away.

    Not practising is not failing: the card keeps its rung, stays due, and waits.
    At fifty cards a week more is due than any session can hold, and punishing
    the reader for that arithmetic would be punishing them for collecting.
    """
    weeks_later = TODAY + timedelta(days=21)

    assert move(rung=2, last_move_on=TODAY, today=weeks_later, passed=True) == (
        3,
        weeks_later + timedelta(days=21),
    )


# --- the table itself --------------------------------------------------------


def test_the_intervals_are_the_ones_the_prd_states():
    """Pinned so a change is deliberate. The PRD is explicit that no interval
    gets adjusted before there is real data to argue with."""
    assert LADDER_INTERVALS == (1, 3, 7, 21, 60)


@pytest.mark.parametrize("rung", range(len(LADDER_INTERVALS)))
def test_every_rung_yields_a_future_date(rung):
    assert next_due(rung, today=TODAY) > TODAY
