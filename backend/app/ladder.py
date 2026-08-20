"""The across-days schedule: 1 / 3 / 7 / 21 / 60 days.

Two clocks run in this feature and most of the difficulty is keeping them
apart. ``daily_progress`` is the one inside a session — practising until a word
sticks is exactly its purpose. **This one is about recall after a gap**, and it
answers a different question: not "can you get this right now", but "will you
still have it in a week".

That difference is why the rules below look harsh in the moment.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Optional

#: Days until a card is next due, by rung. Index is the rung.
#:
#: A starting guess, and it stays one until there is real data to argue with —
#: the PRD is explicit that no interval gets adjusted before then.
LADDER_INTERVALS = (1, 3, 7, 21, 60)

FIRST_RUNG = 0
TOP_RUNG = len(LADDER_INTERVALS) - 1


def next_due(rung: int, *, today: date) -> date:
    """When a card at ``rung`` should next be asked.

    Counted from the day the move happened, not from the previous due date. A
    card answered four days late is not owed those four days back — the point of
    reference is when the reader actually recalled it.
    """
    return today + timedelta(days=LADDER_INTERVALS[_clamp(rung)])


def rung_after_pass(rung: int) -> int:
    """One rung up, clamped at the top."""
    return _clamp(rung + 1)


def rung_after_failure(rung: int) -> int:
    """Straight back to the bottom, from any height.

    **Not one rung down.** A card forgotten at sixty days would then be next
    asked in twenty-one — a long wait after just proving it is gone. The point
    of an interval is that it reflects what the reader retains, and a card they
    have just missed retains nothing worth scheduling far out.
    """
    return FIRST_RUNG


def _clamp(rung: int) -> int:
    return max(FIRST_RUNG, min(TOP_RUNG, rung))


def move(
    *,
    rung: int,
    last_move_on: Optional[date],
    today: date,
    passed: bool,
) -> Optional[tuple[int, date]]:
    """The card's new rung and due date, or ``None`` when nothing should change.

    **At most one move per day**, and the day's *first* resolution decides it.
    So a card answered wrong early does not recover its rung by being drilled to
    通過 later the same day — and that is deliberate, however unfair it feels in
    the moment, because the reader *did* end the session knowing the word.

    The reason is what this clock measures. The gap already happened: they met
    the word today and did not have it. Letting an afternoon of drilling erase
    that would make the ladder a record of effort rather than of memory, and the
    interval it schedules would stop meaning anything.
    """
    if last_move_on == today:
        return None
    new_rung = rung_after_pass(rung) if passed else rung_after_failure(rung)
    return new_rung, next_due(new_rung, today=today)
