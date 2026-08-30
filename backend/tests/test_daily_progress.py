"""The three-step day (vocabulary stage 4, ticket 02).

A pure function over one day's answers, so the whole table is testable without
a database or a screen — which is the point of deriving the step rather than
storing it.

The case worth reading first is `test_correct_wrong_correct_does_not_pass`:
passing needs two correct answers **in a row**, not two correct answers. An
implementation that counted them would pass a card the reader plainly does not
have yet, and would do it silently.
"""

from __future__ import annotations

import pytest

from app.daily_progress import DailyStep, step_after, step_today


# --- the table, transition by transition -------------------------------------


@pytest.mark.parametrize(
    "start,correct,expected",
    [
        (DailyStep.UNSEEN, True, DailyStep.FAMILIAR),
        (DailyStep.UNSEEN, False, DailyStep.UNFAMILIAR),
        (DailyStep.UNFAMILIAR, True, DailyStep.FAMILIAR),
        (DailyStep.UNFAMILIAR, False, DailyStep.UNFAMILIAR),
        (DailyStep.FAMILIAR, True, DailyStep.PASSED),
        (DailyStep.FAMILIAR, False, DailyStep.UNFAMILIAR),
        (DailyStep.PASSED, True, DailyStep.PASSED),
        (DailyStep.PASSED, False, DailyStep.UNFAMILIAR),
    ],
)
def test_every_transition(start, correct, expected):
    assert step_after(start, correct) is expected


def test_a_first_correct_answer_skips_unfamiliar(clean_slate=None):
    """Getting it right first time is evidence.

    Climbing a step the card never fell to would mean a word the reader clearly
    knows needs three answers to pass rather than two.
    """
    assert step_today([True]) is DailyStep.FAMILIAR


def test_two_correct_in_a_row_passes_the_day():
    assert step_today([True, True]) is DailyStep.PASSED


def test_correct_wrong_correct_does_not_pass():
    """**Two in a row**, not two in total.

    Counting them would pass a card the reader missed in between, which is
    precisely the card the day exists to catch.
    """
    assert step_today([True, False, True]) is DailyStep.FAMILIAR


def test_a_wrong_answer_returns_to_the_bottom_from_anywhere():
    assert step_today([True, True, False]) is DailyStep.UNFAMILIAR
    assert step_today([True, False]) is DailyStep.UNFAMILIAR
    assert step_today([False]) is DailyStep.UNFAMILIAR


def test_drilling_a_passed_card_cannot_push_it_further():
    """`passed` is the top. There is nowhere above it to reach by answering
    more, so a long session cannot inflate a day's result."""
    assert step_today([True, True, True, True, True]) is DailyStep.PASSED


# --- what "no answers" means -------------------------------------------------


def test_a_card_with_no_answers_today_is_unseen_rather_than_unfamiliar():
    """A card that has never been asked is not a card that has just been failed.

    Collapsing the two would make every untouched card look like a failure, and
    a reader returning after a week would find their whole deck at the bottom.
    """
    assert step_today([]) is DailyStep.UNSEEN
    assert step_today([]) is not DailyStep.UNFAMILIAR


def test_a_gap_of_any_length_looks_the_same():
    """One day away and three weeks away are the same thing here.

    There is no settlement moment, so nothing runs late and nothing runs
    repeatedly to catch up — the caller simply passes today's answers, and on a
    day with none there are none.
    """
    assert step_today([]) is DailyStep.UNSEEN


# --- order is part of the input ----------------------------------------------


def test_order_changes_the_answer():
    """Replayed oldest first. Reversed, the same rows describe a day that did
    not happen — which is why the store returns them ascending."""
    assert step_today([False, True, True]) is DailyStep.PASSED
    assert step_today([True, True, False]) is DailyStep.UNFAMILIAR
