"""What one answer does to a card: the state machine, as a pure function.

The model is Anki's, which is SM-2's, with this project's binary grading. A card
walks a short list of **learning steps** measured in minutes, and on clearing
the last one it **graduates** onto ``ladder``'s interval table, measured in
days. A graduated card answered wrong walks the steps again and comes back one
slot lower than it was.

**It replaces the three-step day**, which was derived by replaying a day's
answers and reset at midnight -- so a card left half-learned when the reader put
the phone down was back at first sight the next morning, and their two answers
had bought nothing. That reset is the mechanism behind the first acceptance
pass's "I have practised this card several times and it still says New".

Nothing here reads a clock. ``answered_at`` is a parameter because an answer
given in airplane mode arrives hours after it happened, and scheduling it from
the moment it arrived would put a five-minute step in the wrong afternoon.
Settings are parameters for the same reason: the reader can change them, and a
function that reached for the current ones could not be tested against a
three-step list and a five-step list in the same run.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from enum import Enum
from typing import Optional, Sequence

from . import ladder

#: Minutes between learning steps, before a card graduates. Adjustable by the
#: reader (stage 6 ticket 06); this is the default, and Anki's own default of
#: 1m/10m was widened because a session here is one sitting rather than a queue
#: the reader grinds down.
DEFAULT_LEARNING_STEPS = (5, 7, 10)

#: How many cards may be met for the first time in one day, by default.
DEFAULT_NEW_CARDS_PER_DAY = 15


class CardState(str, Enum):
    """Where a card is in the model.

    Stored on the card rather than derived from its answers, which is a reversal
    of the three-step day's design and is forced by two things: a learning
    card's position is *which step, due at what minute*, a dimension the review
    log has never carried; and stage 6's migration resets every card while
    keeping every review row, so "has answers" stops meaning "has been met".
    """

    #: Never answered, or reset by a migration. Waits for the day's new-card
    #: quota rather than for a due date.
    NEW = "new"
    #: Walking the learning steps for the first time.
    LEARNING = "learning"
    #: Graduated, on the interval table.
    REVIEW = "review"
    #: Graduated once, then missed. Walking the same steps back to its slot.
    RELEARNING = "relearning"


@dataclass(frozen=True)
class CardSchedule:
    """Everything scheduling knows about one card.

    A value, not a row: the same shape comes out of the database, goes into
    ``next_schedule``, and comes back to be written. Keeping it separate from
    the ORM object is what lets the transitions be tested without a database.
    """

    state: CardState
    #: Index into the learning steps, or ``None`` outside the learning states.
    learning_step: Optional[int]
    #: Which slot of ``ladder.LADDER_INTERVALS``.
    stage: int
    #: The slot to return to on graduating from ``RELEARNING``. ``None`` when
    #: the card has never lapsed, or has already used it.
    previous_stage: Optional[int]
    due_at: datetime


def new_card(*, now: datetime) -> CardSchedule:
    """A freshly collected card: due immediately, waiting on the quota."""
    return CardSchedule(
        state=CardState.NEW,
        learning_step=None,
        stage=ladder.FIRST_SLOT,
        previous_stage=None,
        due_at=now,
    )


def next_schedule(
    current: CardSchedule,
    *,
    correct: bool,
    answered_at: datetime,
    learning_steps: Sequence[int] = DEFAULT_LEARNING_STEPS,
) -> CardSchedule:
    """Where ``current`` goes after one answer.

    ================  ===============================  ========================
    From              Correct                          Wrong
    ================  ===============================  ========================
    ``NEW``           learning, step 0                 learning, step 0
    learning step i   step i+1                         step 0
    learning, last    graduates                        step 0
    ``REVIEW`` n      slot n+1 (clamped at the top)    relearning, keeping n-1
    ``RELEARNING``    as learning                      step 0
    ================  ===============================  ========================

    **A ``REVIEW`` card answered before ``due_at`` is returned unchanged**, in
    either direction. See the comment on that branch: the interval is the claim
    being tested, and an answer given early has not tested it.

    **A first answer that is wrong still only reaches the first step.** There is
    nothing below the bottom to fall to, and inventing a punishment there would
    charge the reader for meeting a word.

    **Graduating goes to ``previous_stage`` when there is one**, which is what
    makes a lapse cost one slot instead of everything: 60 days -> missed -> the
    steps again -> 21 days, not 1. The old ladder fell all the way, which was
    defensible when a wrong answer was rare and is not now that judging is an
    exact match on production -- one word out of place in a Vietnamese sentence
    is wrong, and charging a year of progress for it teaches nothing.

    ``previous_stage`` is **cleared once used**, so a second lapse from slot 5
    returns to 4 rather than to whatever the first lapse remembered.
    """
    steps = tuple(learning_steps)
    if not steps or any(minutes <= 0 for minutes in steps):
        raise ValueError("learning steps must be a non-empty list of positive minutes")

    def at_step(state: CardState, index: int) -> CardSchedule:
        # Clamped, because the reader may have shortened the list under a card
        # already past the new end of it.
        bounded = max(0, min(index, len(steps) - 1))
        return replace(
            current,
            state=state,
            learning_step=bounded,
            due_at=answered_at + timedelta(minutes=steps[bounded]),
        )

    def graduated() -> CardSchedule:
        slot = ladder.clamp_slot(
            current.previous_stage
            if current.previous_stage is not None
            else ladder.FIRST_SLOT
        )
        return CardSchedule(
            state=CardState.REVIEW,
            learning_step=None,
            stage=slot,
            previous_stage=None,
            due_at=ladder.due_after(slot, answered_at),
        )

    if current.state is CardState.NEW:
        return at_step(CardState.LEARNING, 0)

    if current.state in (CardState.LEARNING, CardState.RELEARNING):
        if not correct:
            return at_step(current.state, 0)
        index = max(0, min(current.learning_step or 0, len(steps) - 1))
        if index >= len(steps) - 1:
            return graduated()
        return at_step(current.state, index + 1)

    # REVIEW.
    #
    # **An answer that arrives before the card is due moves nothing.** It is
    # recorded like any other -- what the reader did is a fact -- but it cannot
    # promote a slot, and by the same sentence it cannot cost one either: an
    # answer that is not allowed to earn anything must not be allowed to charge
    # anything.
    #
    # The interval is the claim being tested. A card that graduated onto "one
    # day" an hour ago has not survived a day, so answering it correctly now
    # says nothing about whether three days is the right next question, and
    # promoting it would teach the schedule something that did not happen.
    #
    # In practice this is also the guard against being asked twice. The queue
    # lives in the app and is built from a deck the app holds; a dropped
    # response leaves that deck believing a graduated card is still due, and it
    # will offer it again. The card's own due date is the only thing in the
    # system that can refuse.
    #
    # The learning steps are deliberately not covered: ``learnAheadWindow``
    # offers a learning card up to twenty minutes early **on purpose**, and a
    # duplicate there costs one step and heals itself.
    if answered_at < current.due_at:
        return current

    if correct:
        slot = ladder.clamp_slot(current.stage + 1)
        return CardSchedule(
            state=CardState.REVIEW,
            learning_step=None,
            stage=slot,
            previous_stage=None,
            due_at=ladder.due_after(slot, answered_at),
        )
    return replace(
        at_step(CardState.RELEARNING, 0),
        previous_stage=ladder.clamp_slot(current.stage - 1),
    )
