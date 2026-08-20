"""Repository for card reviews — every answer, exactly as it happened.

Thin functions over a SQLAlchemy ``Session``, the shape ``progress_store``,
``comprehension_store`` and ``learning_card_store`` already use.

These rows are the unit the whole reviewing system is computed from. A card's
position in the three-step day is **derived by replaying today's rows**, not
stored, which is what makes a gap in practice cost nothing: there is no
settlement moment, so nothing runs late, nothing runs three times, and a day the
reader skipped is a day with no rows in it.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import ladder
from .daily_progress import passed_today
from .db import CardReview, LearningCard

# What kind of question produced an answer. Recorded rather than inferred, since
# the same card can be asked in more than one way and the difference matters to
# anything that later weighs difficulty.
QUESTION_CLOZE_CHOICE = "cloze_choice"
QUESTION_CLOZE_TYPED = "cloze_typed"
QUESTION_SENTENCE_REARRANGED = "sentence_rearranged"
QUESTION_SENTENCE_TYPED = "sentence_typed"
QUESTION_TYPES = frozenset({
    QUESTION_CLOZE_CHOICE,
    QUESTION_CLOZE_TYPED,
    QUESTION_SENTENCE_REARRANGED,
    QUESTION_SENTENCE_TYPED,
})


def record(
    session: Session,
    *,
    card_id: int,
    question_type: str,
    is_correct: bool,
    client_token: str,
    local_date: date,
    elapsed_ms: Optional[int] = None,
) -> Tuple[CardReview, bool]:
    """Record one answer; return it and whether it was new.

    **Idempotent on ``client_token``.** A tapped button on a slow connection is
    exactly how one answer becomes two, and a duplicated wrong answer would drop
    a rung the reader never lost. A replay returns the row already stored rather
    than failing, so the client needs no special case for it.
    """
    existing = session.execute(
        select(CardReview).where(CardReview.client_token == client_token)
    ).scalar_one_or_none()
    if existing is not None:
        return existing, False

    review = CardReview(
        card_id=card_id,
        question_type=question_type,
        is_correct=is_correct,
        elapsed_ms=elapsed_ms,
        client_token=client_token,
        local_date=local_date,
        reviewed_at=datetime.now(timezone.utc),
    )
    session.add(review)
    try:
        session.commit()
    except IntegrityError:
        # Two submissions of the same answer raced past the check above. The
        # constraint did its job; read back what it kept.
        session.rollback()
        winner = session.execute(
            select(CardReview).where(CardReview.client_token == client_token)
        ).scalar_one()
        return winner, False
    session.refresh(review)
    return review, True


def for_card(session: Session, card_id: int) -> List[CardReview]:
    """One card's answers, **oldest first** — the order a day is replayed in."""
    rows = session.execute(
        select(CardReview)
        .where(CardReview.card_id == card_id)
        .order_by(CardReview.reviewed_at.asc(), CardReview.id.asc())
    ).scalars()
    return list(rows)


def on_day(session: Session, card_id: int, day: date) -> List[CardReview]:
    """One card's answers on ``day`` (UTC), oldest first.

    The three-step day is computed from exactly this list. Anything outside it
    is a different day and has no bearing — which is the whole reason a reader
    can be away for three weeks and come back to a card sitting where they left
    it.
    """
    rows = session.execute(
        select(CardReview)
        .where(
            CardReview.card_id == card_id,
            # The reader's day, not the server's — see `CardReview.local_date`.
            CardReview.local_date == day,
        )
        .order_by(CardReview.reviewed_at.asc(), CardReview.id.asc())
    ).scalars()
    return list(rows)


def card_exists(session: Session, card_id: int) -> bool:
    """Whether there is a card to record against.

    Checked before writing so an answer for a deleted card is a 404 rather than
    a row pointing at nothing.
    """
    return session.get(LearningCard, card_id) is not None


def apply_ladder_move(session: Session, card_id: int, *, today: date) -> bool:
    """Move the card's rung if today's answers call for it; report whether it moved.

    Run after each answer, and idempotent for the rest of the day by design:
    ``ladder.move`` refuses a second move once ``last_ladder_move_on`` is today,
    so this can be called on every submission without counting twice.

    **The day's first resolution decides it.** A wrong answer resolves the day
    immediately; a correct one resolves it only on reaching 通過, since one
    correct answer is not yet a pass. Anything in between leaves the card open
    and the rung untouched.
    """
    card = session.get(LearningCard, card_id)
    if card is None:
        return False

    answers = [row.is_correct for row in on_day(session, card_id, today)]
    if not answers:
        return False

    passed = passed_today(answers)
    # Nothing has resolved yet: still climbing, and not yet fallen.
    if not passed and all(answers):
        return False

    outcome = ladder.move(
        rung=card.ladder_stage,
        last_move_on=card.last_ladder_move_on,
        today=today,
        passed=passed,
    )
    if outcome is None:
        return False

    card.ladder_stage, card.due_on = outcome
    card.last_ladder_move_on = today
    session.commit()
    return True
