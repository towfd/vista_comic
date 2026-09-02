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
from zoneinfo import ZoneInfo

import pytest

from app.ladder import (
    DAY_ROLLOVER_HOUR,
    FIRST_SLOT,
    LADDER_INTERVALS,
    TOP_SLOT,
    clamp_slot,
    due_after,
    interval_days,
)

TAIPEI = ZoneInfo("Asia/Taipei")

#: 2026-09-01 05:15 in Taipei -- an ordinary morning, past the rollover.
MOMENT = datetime(2026, 8, 31, 21, 15, tzinfo=timezone.utc)


def taipei(year, month, day, hour=0, minute=0) -> datetime:
    """A moment written the way the reader would say it."""
    return datetime(year, month, day, hour, minute, tzinfo=TAIPEI)


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
    assert due_after(slot, MOMENT, tz=TAIPEI) > MOMENT


def test_the_due_time_comes_from_the_slot():
    """Answered on the morning of the 1st, slot 0 comes back on the 2nd."""
    assert due_after(0, MOMENT, tz=TAIPEI) == taipei(2026, 9, 2, DAY_ROLLOVER_HOUR)
    assert due_after(TOP_SLOT, MOMENT, tz=TAIPEI) == taipei(
        2027, 9, 1, DAY_ROLLOVER_HOUR
    )


def test_the_due_time_is_counted_from_the_answer_not_the_last_due_date():
    """A card answered four days late is not owed those four days back.

    The point of reference is when the reader actually recalled it.
    """
    late = MOMENT + timedelta(days=4)
    assert due_after(2, late, tz=TAIPEI) == taipei(2026, 9, 12, DAY_ROLLOVER_HOUR)


def test_a_late_night_answer_comes_back_the_next_morning():
    """The reason this rule exists.

    Finishing at 23:59 used to mean "back at 23:59 tomorrow" -- one day later
    to the second, and the worst hour of the day to be asked. A day-length
    interval means the next day, so it lands on the morning.
    """
    landed = due_after(0, taipei(2026, 9, 1, 23, 59), tz=TAIPEI)

    assert landed == taipei(2026, 9, 2, DAY_ROLLOVER_HOUR)


def test_answers_anywhere_in_one_day_come_back_together():
    """What "measured in days" actually claims.

    Three answers spread across a Tuesday are all one day from Tuesday, so all
    three come back on Wednesday morning -- not at breakfast, lunch and
    midnight respectively.
    """
    morning = due_after(0, taipei(2026, 9, 1, 9, 0), tz=TAIPEI)
    evening = due_after(0, taipei(2026, 9, 1, 21, 0), tz=TAIPEI)
    last_thing = due_after(0, taipei(2026, 9, 1, 23, 59), tz=TAIPEI)

    assert morning == evening == last_thing


def test_an_answer_before_the_rollover_belongs_to_the_night_before():
    """02:00 on Wednesday is still Tuesday night.

    This is the whole point of rolling over at four rather than at midnight,
    and it cuts both ways: the reader still up at two gets the rest of "their"
    Tuesday, and the card they answer then is due when Wednesday starts.
    """
    landed = due_after(0, taipei(2026, 9, 2, 2, 0), tz=TAIPEI)

    assert landed == taipei(2026, 9, 2, DAY_ROLLOVER_HOUR)


def test_the_rollover_hour_survives_a_daylight_saving_change():
    """Still four in the morning on the far side of a clock change.

    Taipei never changes its clocks, so this is asserted in a zone that does.
    Adding 24-hour blocks would land at three or five; rebuilding the due date
    from the calendar day lands on four.
    """
    new_york = ZoneInfo("America/New_York")
    # 2026-11-01 is the US autumn change; answering on the 30th of October
    # puts slot 1 (three days) on the far side of it.
    answered = datetime(2026, 10, 30, 20, 0, tzinfo=new_york)

    landed = due_after(1, answered, tz=new_york).astimezone(new_york)

    assert (landed.year, landed.month, landed.day) == (2026, 11, 2)
    assert landed.hour == DAY_ROLLOVER_HOUR


def test_the_zone_is_the_callers_business():
    """The same instant is a different day depending on whose day it is.

    22:00 UTC on the 1st is already the 2nd in Taipei, so the two zones put the
    card on different mornings -- which is why the zone is a parameter rather
    than something this module looks up.
    """
    answered = datetime(2026, 9, 1, 22, 0, tzinfo=timezone.utc)

    in_taipei = due_after(0, answered, tz=TAIPEI)
    in_utc = due_after(0, answered, tz=timezone.utc)

    assert in_taipei == taipei(2026, 9, 3, DAY_ROLLOVER_HOUR)
    assert in_utc == datetime(2026, 9, 2, DAY_ROLLOVER_HOUR, tzinfo=timezone.utc)


def test_a_slot_past_either_end_is_clamped():
    assert clamp_slot(-3) == FIRST_SLOT
    assert clamp_slot(99) == TOP_SLOT
    assert interval_days(99) == 365
