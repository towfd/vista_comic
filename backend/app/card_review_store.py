"""Repository for card reviews — every answer, exactly as it happened.

Thin functions over a SQLAlchemy ``Session``, the shape ``progress_store``,
``comprehension_store`` and ``learning_card_store`` already use.

These rows are the complete record of what the reader did. They no longer decide
where a card stands -- stage 6 moved that to a stored state, because a learning
card's position is *which step, due at what minute*, a dimension no row here has
ever carried, and because the stage 6 migration resets cards while keeping their
rows. What the log is still for is unchanged: it is kept complete so that
adopting FSRS later is an algorithm change rather than a migration.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import config, scheduler, study_settings_store
from .db import CardReview, LearningCard
from .scheduler import CardSchedule, CardState

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

# Which mode asked the question. 永無止盡的訓練 records every answer and
# schedules nothing, so without this the log could not tell an answer that was
# meant to count from one that deliberately did not.
CONTEXT_REVIEW = "review"
CONTEXT_TRAINING = "training"
CONTEXTS = frozenset({CONTEXT_REVIEW, CONTEXT_TRAINING})


def record(
    session: Session,
    *,
    card_id: int,
    question_type: str,
    is_correct: bool,
    client_token: str,
    local_date: date,
    answered_at: datetime,
    context: str = CONTEXT_REVIEW,
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
        context=context,
        # When the reader answered, which is theirs to report; and when it
        # reached us, which is ours. They are the same moment online and hours
        # apart after an offline session flushes.
        answered_at=answered_at,
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


def card_exists(session: Session, card_id: int) -> bool:
    """Whether there is a card to record against.

    Checked before writing so an answer for a deleted card is a 404 rather than
    a row pointing at nothing.
    """
    return session.get(LearningCard, card_id) is not None


def schedule_of(card: LearningCard) -> CardSchedule:
    """The card's scheduling state, as a value the pure function can take."""
    return CardSchedule(
        state=CardState(card.state),
        learning_step=card.learning_step,
        stage=card.ladder_stage,
        previous_stage=card.previous_stage,
        due_at=card.due_at,
    )


def apply_answer(
    session: Session,
    card_id: int,
    *,
    correct: bool,
    answered_at: datetime,
    local_date: Optional[date] = None,
) -> Optional[CardSchedule]:
    """Move the card according to one answer; return where it landed.

    Returns ``None`` only when there is no such card. **Every scheduled answer
    moves something** -- which is the difference from the ladder this replaced,
    where a correct answer that changed no step deliberately changed nothing.
    That rule existed because passing was a state a card could sit in and be
    drilled inside; learning steps have no such resting place, so an answer
    always advances a step, restarts one, or moves a slot.

    Call this only for an answer that was actually **recorded**. A replayed
    submission stores no row and must therefore change nothing, and that check
    is the only thing standing between a retry and a second graduation. The
    caller owns it because only the caller knows whether the row was new.

    Call it only for ``review`` answers, too: 永無止盡的訓練 records and
    schedules nothing, by the reader's decision.
    """
    card = session.get(LearningCard, card_id)
    if card is None:
        return None

    settings = study_settings_store.get(session)
    landed = scheduler.next_schedule(
        schedule_of(card),
        correct=correct,
        answered_at=answered_at,
        learning_steps=settings.learning_steps,
        # Whose day a day-length interval lands on. Configured rather than
        # sent, on the same reasoning `introduced_on` below is the reader's day
        # rather than the server's -- a UTC boundary would roll the schedule
        # over at noon on UTC+8.
        scheduling_timezone=config.get_scheduling_timezone(),
    )
    # The day the card stopped being new, in the reader's terms rather than the
    # server's -- the quota is "how many new words today", and on UTC+8 a UTC
    # boundary would move that line to eight in the morning.
    if card.state == CardState.NEW.value and landed.state is not CardState.NEW:
        card.introduced_on = local_date or answered_at.date()
    card.state = landed.state.value
    card.learning_step = landed.learning_step
    card.ladder_stage = landed.stage
    card.previous_stage = landed.previous_stage
    card.due_at = landed.due_at
    session.commit()
    return landed
