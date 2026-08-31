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

from datetime import datetime, timedelta

#: Days until a card is next due, by slot. Index is the slot.
LADDER_INTERVALS = (1, 3, 7, 21, 60, 150, 365)

FIRST_SLOT = 0
TOP_SLOT = len(LADDER_INTERVALS) - 1


def clamp_slot(slot: int) -> int:
    """``slot`` brought inside the table."""
    return max(FIRST_SLOT, min(TOP_SLOT, slot))


def interval_days(slot: int) -> int:
    """How many days a card at ``slot`` waits."""
    return LADDER_INTERVALS[clamp_slot(slot)]


def due_after(slot: int, moment: datetime) -> datetime:
    """When a card at ``slot`` answered at ``moment`` comes back.

    Counted from the answer, not from the previous due date. A card answered
    four days late is not owed those four days back -- the point of reference is
    when the reader actually recalled it.
    """
    return moment + timedelta(days=interval_days(slot))
