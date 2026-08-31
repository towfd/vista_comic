"""The reader's scheduling settings: one row, read by everything that schedules.

Kept on the backend rather than on the device because the backend recomputes
schedules when an offline session flushes, and two copies that disagreed would
produce two different ``due_at`` values for the same answer.

The row is seeded by the stage 6 migration, so ``get`` finding nothing means a
database that has not been migrated -- but it heals rather than raising, since
refusing to schedule is a worse failure than scheduling on the defaults.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Sequence

from sqlalchemy.orm import Session

from .db import StudySettings
from .scheduler import DEFAULT_LEARNING_STEPS, DEFAULT_NEW_CARDS_PER_DAY

SINGLE_ROW_ID = 1


@dataclass(frozen=True)
class Settings:
    learning_steps: List[int]
    new_cards_per_day: int


def get(session: Session) -> Settings:
    """The settings, seeding the defaults if the row is missing."""
    row = session.get(StudySettings, SINGLE_ROW_ID)
    if row is None:
        row = StudySettings(
            id=SINGLE_ROW_ID,
            learning_steps=list(DEFAULT_LEARNING_STEPS),
            new_cards_per_day=DEFAULT_NEW_CARDS_PER_DAY,
        )
        session.add(row)
        session.commit()
        session.refresh(row)
    return Settings(
        learning_steps=list(row.learning_steps),
        new_cards_per_day=row.new_cards_per_day,
    )


def put(
    session: Session, *, learning_steps: Sequence[int], new_cards_per_day: int
) -> Settings:
    """Replace the settings.

    Validation belongs to the request model; this refuses the two values that
    would break scheduling outright rather than trusting that it ran -- an empty
    step list has no first step to fall back to, and a non-positive step would
    schedule a card to be due before it was answered.
    """
    steps = list(learning_steps)
    if not steps or any(minutes <= 0 for minutes in steps):
        raise ValueError("learning steps must be a non-empty list of positive minutes")
    if new_cards_per_day < 0:
        raise ValueError("new cards per day cannot be negative")

    row = session.get(StudySettings, SINGLE_ROW_ID)
    if row is None:
        row = StudySettings(id=SINGLE_ROW_ID)
        session.add(row)
    row.learning_steps = steps
    row.new_cards_per_day = new_cards_per_day
    session.commit()
    session.refresh(row)
    return Settings(
        learning_steps=list(row.learning_steps),
        new_cards_per_day=row.new_cards_per_day,
    )
