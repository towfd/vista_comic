"""The across-days schedule: 1 / 3 / 7 / 21 / 60 / 150 / 365 days.

The table a card graduates onto once it is out of the learning steps. Those
steps (``scheduler``) run in minutes and ask "can you get this right now"; this
one runs in days and asks the different question — "will you still have it in a
week".

**Seven slots since 2026-08-31**, up from five. The two new entries continue the
table's own ratio rather than extending it flat: 90 and 120 were considered and
rejected, because 60 -> 90 is x1.5 and 90 -> 120 is x1.33, both below the
table's average of about x2.8, which would say that surviving sixty days makes a
card *less* stable. SM-2 grows intervals multiplicatively (``I(n) = I(n-1) x
EF``, EF defaulting to 2.5, which is also Anki's default starting ease), so the
consistent continuation is 150 and 365.

365 is the terminal slot: a card asked once a year is retired without being
deleted.

**What is no longer here**: ``move``, ``rung_after_pass`` and
``rung_after_failure``. They encoded "one wrong answer falls to the bottom",
which stage 6 replaced with a fall of one slot -- and the decision of where a
card goes next now belongs to the state machine in ``scheduler``, which needs to
know about learning steps this module has no business knowing about.
"""

from __future__ import annotations

from datetime import datetime, time, timedelta, timezone, tzinfo

#: Days until a card is next due, by slot. Index is the slot.
LADDER_INTERVALS = (1, 3, 7, 21, 60, 150, 365)

#: The hour a scheduling day begins, in the reader's own timezone.
#:
#: Four in the morning rather than midnight, which is Anki's default and for
#: Anki's reason: the reader reads comics at night, and a card answered at
#: 23:59 with midnight rollover would come back **one minute later**, in the
#: same sitting. A day that ends when the reader goes to sleep is the day they
#: actually live; one that ends at midnight cuts a single evening in half.
DAY_ROLLOVER_HOUR = 4

FIRST_SLOT = 0
TOP_SLOT = len(LADDER_INTERVALS) - 1


def clamp_slot(slot: int) -> int:
    """``slot`` brought inside the table."""
    return max(FIRST_SLOT, min(TOP_SLOT, slot))


def interval_days(slot: int) -> int:
    """How many days a card at ``slot`` waits."""
    return LADDER_INTERVALS[clamp_slot(slot)]


def scheduling_day_start(moment: datetime, *, tz: tzinfo) -> datetime:
    """The start of the scheduling day ``moment`` falls in, as an instant.

    A scheduling day runs from ``DAY_ROLLOVER_HOUR`` to the same hour the next
    calendar day, so anything answered in the small hours belongs to the day
    the reader thinks of as still in progress -- 02:00 on Tuesday is Monday
    night.
    """
    local = moment.astimezone(tz)
    day = local.date()
    if local.hour < DAY_ROLLOVER_HOUR:
        day -= timedelta(days=1)
    return datetime.combine(day, time(DAY_ROLLOVER_HOUR), tzinfo=tz)


def due_after(slot: int, moment: datetime, *, tz: tzinfo) -> datetime:
    """When a card at ``slot`` answered at ``moment`` comes back.

    Counted from the answer, not from the previous due date. A card answered
    four days late is not owed those four days back -- the point of reference is
    when the reader actually recalled it.

    **Measured in days, not in multiples of 24 hours.** The answer is rounded
    down to the start of its scheduling day and the interval is added to *that*,
    so "one day" means "next day", whether the answer came at 09:00 or at 23:59.
    The instant arithmetic this replaced made a card answered late at night come
    back late the following night, which is a worse time to be asked and is not
    what a table measured in days claims to say.

    ``tz`` is a parameter for the same reason ``learning_steps`` is one over in
    ``scheduler``: whose day it is belongs to the caller, and a function that
    reached for the configured zone could not be tested against two of them in
    the same run.

    Returned in UTC, which is what the column stores.
    """
    start = scheduling_day_start(moment, tz=tz)
    due_day = start.date() + timedelta(days=interval_days(slot))
    # Rebuilt from the date rather than by adding a ``timedelta`` to ``start``,
    # so a zone that observes DST lands on the rollover hour on the target day
    # instead of an hour either side of it.
    return datetime.combine(due_day, time(DAY_ROLLOVER_HOUR), tzinfo=tz).astimezone(
        timezone.utc
    )
