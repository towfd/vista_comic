"""The across-days schedule: 1 / 3 / 7 / 21 / 60 days.

Two clocks run in this feature and most of the difficulty is keeping them
apart. ``daily_progress`` is the one inside a session — practising until a word
sticks is exactly its purpose. **This one is about recall after a gap**, and it
answers a different question: not "can you get this right now", but "will you
still have it in a week".

That difference is why a card falls all the way to the bottom on one wrong
answer, however well the rest of the session went.
"""

from __future__ import annotations

from datetime import date, timedelta

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


def move(*, rung: int, today: date, passed: bool) -> tuple[int, date]:
    """The card's new rung and due date.

    **A card may move more than once in a day**, up or down. This used to refuse
    a second move, on the argument that the gap had already happened: the reader
    met the word and did not have it, and an afternoon of drilling should not
    erase that.

    That argument was right about what the ladder measures and wrong about what
    it would do to a new deck. Thirty cards all sat on rung 0; a first encounter
    is very often wrong; one wrong answer locked the card for the day. So
    nothing climbed, the middle rungs were never reached, and the question types
    that live there — typing, rearranging — could not appear at all. A schedule
    that never schedules anything measures nothing either.

    What replaced the lock is not "move on every answer" but **move on the
    answer that changes something** — see ``card_review_store.apply_ladder_move``.
    That is what keeps drilling from ratcheting a card up five rungs in one
    round: reaching 通過 moves it once, and further correct answers change no
    step, so they move nothing.
    """
    new_rung = rung_after_pass(rung) if passed else rung_after_failure(rung)
    return new_rung, next_due(new_rung, today=today)
