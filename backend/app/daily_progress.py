"""Where a card stands *today*: 不熟 → 熟悉 → 通過.

    | Now                    | Correct →      | Wrong → |
    | ---------------------- | -------------- | ------- |
    | first appearance today | 熟悉 (skips 不熟) | 不熟     |
    | 不熟                    | 熟悉            | 不熟     |
    | 熟悉                    | 通過            | 不熟     |

So **two correct answers in a row pass the day**, and one wrong answer anywhere
puts the card back to the bottom of the day's steps.

**Derived, never stored.** There is no column holding the step and no job that
resets one — the position is computed by replaying the day's answers in order.

That is what makes a gap cost nothing. There is no settlement moment, so nothing
runs late, nothing runs three times, and there is no question about what a
missed day should have done: a day the reader did not practise is a day with no
answers in it, and three weeks away is the same as one day away.

**Whose day it is matters.** The boundary is the *reader's* local date, sent by
the app, not the server's UTC one. The existing daily spend cap resets on UTC
because a budget wants a consistent moment; a practice day wants midnight where
the reader is. On UTC+8 a UTC boundary would reset the reader's day at eight in
the morning — so a card passed before breakfast could be passed again after it,
climbing two rungs on what the reader experienced as one day.
"""

from __future__ import annotations

from enum import Enum
from typing import Iterable


class DailyStep(str, Enum):
    """How far through today a card has got."""

    #: Not answered yet today. Distinct from ``unfamiliar``: a card that has
    #: never been asked is not a card that has just been failed.
    UNSEEN = "unseen"
    UNFAMILIAR = "unfamiliar"
    FAMILIAR = "familiar"
    PASSED = "passed"


def step_after(step: DailyStep, correct: bool) -> DailyStep:
    """The step one answer moves a card to.

    A wrong answer always returns to ``unfamiliar`` — including from ``unseen``,
    which is why a first-time miss is not treated as gentler than a later one.
    It is the same fact either way: the reader did not have the word.
    """
    if not correct:
        return DailyStep.UNFAMILIAR
    match step:
        case DailyStep.UNSEEN:
            # Skips `unfamiliar`: getting it right first time is evidence, and
            # making the reader climb a step they never fell to would mean a
            # card they clearly know needs three answers rather than two.
            return DailyStep.FAMILIAR
        case DailyStep.UNFAMILIAR:
            return DailyStep.FAMILIAR
        case DailyStep.FAMILIAR:
            return DailyStep.PASSED
        case DailyStep.PASSED:
            # Already done for the day. Further correct answers change nothing,
            # so drilling a passed card cannot push it further.
            return DailyStep.PASSED


def step_today(answers: Iterable[bool]) -> DailyStep:
    """Replay ``answers`` — today's, oldest first — and return where they end.

    The caller is responsible for passing only today's, in order. Both matter:
    yesterday's answers describe a day that is over, and out-of-order answers
    describe a day that did not happen.
    """
    step = DailyStep.UNSEEN
    for correct in answers:
        step = step_after(step, correct)
    return step


def passed_today(answers: Iterable[bool]) -> bool:
    """Whether the card cleared the day."""
    return step_today(answers) is DailyStep.PASSED
