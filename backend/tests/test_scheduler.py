"""What one answer does to a card (vocabulary stage 6, ticket 01).

The whole state machine, tested without a database or a clock. Two properties
here are load-bearing for later tickets and are asserted directly rather than
left to be inferred:

* the function never reads the current time — ticket 07 calls it with a
  timestamp from hours ago, when an offline session flushes;
* the learning steps are a parameter — ticket 06 lets the reader change both the
  minutes and how many there are.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app import ladder
from app.scheduler import (
    DEFAULT_LEARNING_STEPS,
    CardSchedule,
    CardState,
    new_card,
    next_schedule,
)

ANSWERED = datetime(2026, 8, 31, 20, 0, tzinfo=timezone.utc)
STEPS = (5, 7, 10)


def card(state, *, step=None, stage=0, previous=None) -> CardSchedule:
    return CardSchedule(
        state=state,
        learning_step=step,
        stage=stage,
        previous_stage=previous,
        due_at=ANSWERED - timedelta(days=1),
    )


def answer(subject: CardSchedule, correct: bool, *, steps=STEPS, at=ANSWERED):
    return next_schedule(subject, correct=correct, answered_at=at, learning_steps=steps)


# --- New cards ---------------------------------------------------------------


def test_a_new_card_enters_the_learning_steps():
    landed = answer(new_card(now=ANSWERED), True)
    assert landed.state is CardState.LEARNING
    assert landed.learning_step == 0
    assert landed.due_at == ANSWERED + timedelta(minutes=5)


def test_a_first_answer_that_is_wrong_still_only_reaches_the_first_step():
    """There is nothing below the bottom to fall to.

    A first encounter is very often wrong — that is what a first encounter is —
    and inventing a punishment here would charge the reader for meeting a word.
    """
    landed = answer(new_card(now=ANSWERED), False)
    assert landed.state is CardState.LEARNING
    assert landed.learning_step == 0
    assert landed.due_at == ANSWERED + timedelta(minutes=5)


# --- Walking the steps -------------------------------------------------------


@pytest.mark.parametrize(
    "step,expected_step,expected_minutes", [(0, 1, 7), (1, 2, 10)]
)
def test_a_correct_answer_advances_one_step(step, expected_step, expected_minutes):
    landed = answer(card(CardState.LEARNING, step=step), True)
    assert landed.state is CardState.LEARNING
    assert landed.learning_step == expected_step
    assert landed.due_at == ANSWERED + timedelta(minutes=expected_minutes)


@pytest.mark.parametrize("step", [0, 1, 2])
def test_a_wrong_answer_restarts_the_steps(step):
    landed = answer(card(CardState.LEARNING, step=step), False)
    assert landed.learning_step == 0
    assert landed.due_at == ANSWERED + timedelta(minutes=5)


def test_clearing_the_last_step_graduates_to_the_first_slot():
    landed = answer(card(CardState.LEARNING, step=2), True)
    assert landed.state is CardState.REVIEW
    assert landed.learning_step is None
    assert landed.stage == 0
    assert landed.due_at == ANSWERED + timedelta(days=1)


# --- On the interval table ---------------------------------------------------


def test_a_correct_answer_climbs_one_slot():
    landed = answer(card(CardState.REVIEW, stage=2), True)
    assert landed.state is CardState.REVIEW
    assert landed.stage == 3
    assert landed.due_at == ANSWERED + timedelta(days=21)


def test_the_top_slot_clamps_rather_than_overflowing():
    landed = answer(card(CardState.REVIEW, stage=ladder.TOP_SLOT), True)
    assert landed.stage == ladder.TOP_SLOT
    assert landed.due_at == ANSWERED + timedelta(days=365)


def test_a_wrong_answer_starts_relearning_and_remembers_one_slot_down():
    landed = answer(card(CardState.REVIEW, stage=4), False)
    assert landed.state is CardState.RELEARNING
    assert landed.learning_step == 0
    assert landed.previous_stage == 3
    assert landed.due_at == ANSWERED + timedelta(minutes=5)


def test_a_lapse_from_the_top_returns_to_the_slot_below_it():
    """Sixty days does not become one.

    Judging is an exact match on production — one word out of place in a
    Vietnamese sentence is wrong — so charging a year of progress for a slip
    teaches nothing. The old ladder fell all the way; this is the change.
    """
    lapsed = answer(card(CardState.REVIEW, stage=6), False)
    assert lapsed.previous_stage == 5

    relearned = lapsed
    for _ in range(3):
        relearned = answer(relearned, True)
    assert relearned.state is CardState.REVIEW
    assert relearned.stage == 5
    assert relearned.due_at == ANSWERED + timedelta(days=150)


def test_a_lapse_from_the_bottom_slot_stays_at_the_bottom():
    landed = answer(card(CardState.REVIEW, stage=0), False)
    assert landed.previous_stage == 0


def test_the_remembered_slot_is_cleared_once_it_is_used():
    """So a second lapse from slot 5 returns to 4, not to what the first kept."""
    graduated = answer(card(CardState.RELEARNING, step=2, previous=5), True)
    assert graduated.stage == 5
    assert graduated.previous_stage is None

    # A hundred and fifty days later, which is when it is next asked. Answering
    # it at the same instant it graduated would now change nothing (ticket 09),
    # and it is the honest reading of the story anyway.
    lapsed_again = answer(graduated, False, at=graduated.due_at)
    assert lapsed_again.previous_stage == 4


def test_relearning_restarts_on_a_wrong_answer_without_forgetting_the_slot():
    landed = answer(card(CardState.RELEARNING, step=1, previous=3), False)
    assert landed.state is CardState.RELEARNING
    assert landed.learning_step == 0
    assert landed.previous_stage == 3


# --- Answered before it was due (ticket 09) ----------------------------------


def not_yet_due(stage: int) -> CardSchedule:
    """A review card with a day still to run."""
    return CardSchedule(
        state=CardState.REVIEW,
        learning_step=None,
        stage=stage,
        previous_stage=None,
        due_at=ANSWERED + timedelta(days=1),
    )


@pytest.mark.parametrize("correct", [True, False])
def test_a_review_card_answered_early_does_not_move(correct):
    """The interval is the claim, and an early answer has not tested it.

    This is the fifth answer in the bug report: a card graduated onto one day,
    was asked again in the same session because the app's deck had not heard
    about it, and was promoted to three. Nothing had happened in between to
    justify three.

    Wrong answers are covered by the same rule for symmetry — an answer that
    cannot earn a slot must not be able to cost one either.
    """
    subject = not_yet_due(2)
    assert answer(subject, correct) == subject


def test_the_moment_it_is_due_it_moves_again():
    """The boundary is `answered_at < due_at`, not a grace period.

    A card due at 08:00 answered at 08:00 is being answered on time, and the
    day's session is the one that must count.
    """
    subject = not_yet_due(2)
    landed = answer(subject, True, at=subject.due_at)
    assert landed.stage == 3


def test_a_learning_card_answered_early_still_advances():
    """`learnAheadWindow` offers a learning card up to twenty minutes early on
    purpose, so the rule above must not reach it — a session with three cards on
    five-minute timers would otherwise be unable to move at all."""
    subject = CardSchedule(
        state=CardState.LEARNING,
        learning_step=0,
        stage=0,
        previous_stage=None,
        due_at=ANSWERED + timedelta(minutes=4),
    )
    landed = answer(subject, True)
    assert landed.learning_step == 1


# --- The two properties later tickets depend on ------------------------------


def test_the_scheduler_reads_no_clock_of_its_own():
    """Everything is measured from `answered_at`, including a stale one.

    An answer given in airplane mode arrives hours after it happened. Scheduling
    it from the moment it arrived would put a five-minute step in the wrong
    afternoon, so the timestamp has to come in rather than be looked up.
    """
    long_ago = datetime(2026, 1, 1, 9, 30, tzinfo=timezone.utc)
    landed = answer(card(CardState.LEARNING, step=0), True, at=long_ago)
    assert landed.due_at == long_ago + timedelta(minutes=7)


def test_a_different_step_list_schedules_differently():
    landed = answer(card(CardState.LEARNING, step=0), True, steps=(1, 20))
    assert landed.due_at == ANSWERED + timedelta(minutes=20)
    assert answer(landed, True, steps=(1, 20)).state is CardState.REVIEW


def test_a_single_step_list_graduates_on_the_first_correct_answer():
    landed = answer(card(CardState.LEARNING, step=0), True, steps=(3,))
    assert landed.state is CardState.REVIEW


def test_a_card_past_the_end_of_a_shortened_list_is_clamped_not_lost():
    """The reader may cut 5/7/10 down to 5/7 under a card already on step 2."""
    landed = answer(card(CardState.LEARNING, step=2), True, steps=(5, 7))
    assert landed.state is CardState.REVIEW
    assert landed.due_at == ANSWERED + timedelta(days=1)


@pytest.mark.parametrize("steps", [(), (0, 5), (5, -1)])
def test_an_unusable_step_list_is_refused(steps):
    """A zero-minute step would schedule a card before it was answered."""
    with pytest.raises(ValueError):
        answer(card(CardState.LEARNING, step=0), True, steps=steps)


def test_the_defaults_are_the_ones_the_spec_states():
    assert DEFAULT_LEARNING_STEPS == (5, 7, 10)
