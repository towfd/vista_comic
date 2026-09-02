"""Repository for learning cards (the 單字庫 store).

Thin functions over a SQLAlchemy ``Session``, the shape ``progress_store`` and
``comprehension_store`` already use — no repository class.

Like ``comprehension_store`` and unlike ``progress_store``, there are no
degrade-to-default read wrappers: these rows *are* the data, with no independent
source of truth on disk to fall back to, so a store failure surfaces to the
caller (503 in ``main.py``). Reporting "the store is unreachable" as "your
vocabulary is empty" would be a lie the reader cannot detect.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy import delete as delete_stmt, func, select
from sqlalchemy import update as update_stmt
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import scheduler
from .db import LearningCard
from .normalization import normalized_key

# Which interval slot a card starts on. A new card does not wait on this -- it
# waits on the day's new-card quota -- but the column has to hold something, and
# the bottom of the table is what it will graduate onto.
INITIAL_LADDER_STAGE = 0

# What the reader can say a line is, by which of the two save buttons they
# pressed. Anything else is refused rather than stored: an unrecognised kind
# would reach stage 3 as a card no question type knows how to ask about.
KIND_WORD = "word"
KIND_SENTENCE = "sentence"
CARD_KINDS = frozenset({KIND_WORD, KIND_SENTENCE})

# The longest line that can become a card. A guard against a stray whole-page
# selection, not a feature: real speech bubbles are far shorter, and a card the
# reader cannot read at a glance is not reviewable anyway.
MAX_SOURCE_TEXT_LENGTH = 200


def create_or_get(
    session: Session,
    *,
    source_text: str,
    translation: str,
    target_language: str,
    comic_id: str,
    chapter_id: str,
    page_number: int,
    kind: Optional[str] = None,
) -> Tuple[LearningCard, bool]:
    """Collect ``source_text``; return the card and whether it was new.

    **Idempotent on the card's identity**, rather than conflicting. The app's
    offline queue replays whatever it could not send, blindly and possibly more
    than once, and a replay must not be an error — so an existing card comes
    back with ``created=False`` and the endpoint answers 200 instead of 409.

    **An existing card keeps its ``kind``**, even when this call carries a
    different one. Collecting the same line under the other button is not a
    correction — the system does not silently rewrite something the reader
    already approved. Changing it is done in 單字庫.

    An archived card is **revived** rather than returned as-is. The unique
    constraint spans archived rows, so without this the reader could press add,
    be told the word is collected, and never find it in a list that excludes
    archived cards.

    The caller is responsible for rejecting an empty normalised key; this
    function would happily store one.
    """
    key = normalized_key(source_text)
    existing = session.execute(
        select(LearningCard).where(
            LearningCard.normalized_key == key,
            LearningCard.target_language == target_language,
        )
    ).scalar_one_or_none()
    if existing is not None:
        return _revive_if_archived(session, existing), False

    card = LearningCard(
        source_text=source_text,
        normalized_key=key,
        translation=translation,
        target_language=target_language,
        comic_id=comic_id,
        chapter_id=chapter_id,
        page_number=page_number,
        comprehension_record_id=None,
        kind=kind,
        state=scheduler.CardState.NEW.value,
        learning_step=None,
        ladder_stage=INITIAL_LADDER_STAGE,
        previous_stage=None,
        # In the past rather than in the future: a new card is held back by the
        # day's quota, not by a due date, and a timestamp that has already
        # passed says "ready whenever you are" without pretending to schedule.
        due_at=datetime.now(timezone.utc),
        lookup_count=0,
        last_looked_up_at=None,
        # The database clock is the source of truth for this, matching
        # ``progress_store.upsert`` and ``comprehension_store.insert_record``.
        created_at=func.now(),
        archived_at=None,
    )
    session.add(card)
    try:
        session.commit()
    except IntegrityError:
        # Another request won the race between the select above and this
        # commit. The constraint did its job; read back what it kept.
        session.rollback()
        winner = session.execute(
            select(LearningCard).where(
                LearningCard.normalized_key == key,
                LearningCard.target_language == target_language,
            )
        ).scalar_one()
        return _revive_if_archived(session, winner), False
    session.refresh(card)
    return card, True


def _revive_if_archived(session: Session, card: LearningCard) -> LearningCard:
    if card.archived_at is None:
        return card
    card.archived_at = None
    session.commit()
    session.refresh(card)
    return card


def list_active(session: Session) -> List[LearningCard]:
    """Every card the reader still has, newest first.

    Ordered by id alongside ``created_at`` so two cards collected in the same
    clock tick — which the offline queue's flush makes ordinary rather than
    theoretical — still come back in a stable order.
    """
    rows = session.execute(
        select(LearningCard)
        .where(LearningCard.archived_at.is_(None))
        .order_by(LearningCard.created_at.desc(), LearningCard.id.desc())
    ).scalars()
    return list(rows)


def get(session: Session, card_id: int) -> Optional[LearningCard]:
    return session.get(LearningCard, card_id)


def update(
    session: Session,
    card_id: int,
    *,
    translation: Optional[str] = None,
    kind: Optional[str] = None,
    set_kind: bool = False,
) -> bool:
    """Change what the reader is allowed to change; report whether a row existed.

    ``set_kind`` exists because ``None`` is a legitimate new value here: a card
    collected before the two save buttons has no kind, and clearing a wrong
    answer has to be possible. The caller decides whether ``kind`` was *given*;
    this function does not try to infer it from the value.

    Nothing else is touched. ``ladder_stage``, ``due_at``, ``lookup_count`` and
    ``created_at`` are the scheduler's business, and the identity columns
    are nobody's -- see ``models.LearningCardUpdate``.
    """
    values = {}
    if translation is not None:
        values["translation"] = translation
    if set_kind:
        values["kind"] = kind
    if not values:
        return session.get(LearningCard, card_id) is not None

    result = session.execute(
        update_stmt(LearningCard).where(LearningCard.id == card_id).values(**values)
    )
    session.commit()
    return result.rowcount > 0


def delete(session: Session, card_id: int) -> bool:
    """Remove one card; report whether it was there.

    A real delete, not a flag. Archiving was considered and dropped: a word on
    the table's top slot is already scheduled once a year, which is what "I know
    this one" would have meant, so a second concept saying the same thing would
    have had no consumer.
    """
    result = session.execute(delete_stmt(LearningCard).where(LearningCard.id == card_id))
    session.commit()
    return result.rowcount > 0


def reset(session: Session, card_id: int) -> bool:
    """Put one card back to never-having-been-met; report whether it existed.

    What the reader means by "I do not actually know this one". The scheduling
    columns go back to exactly what ``create`` writes -- taken from
    ``scheduler.new_card`` rather than restated here, so "reset" and "freshly
    collected" cannot drift into two different ideas of a new card.

    **The review log is kept.** Nothing schedules from it since stage 6 (see
    ``db.LearningCard.state``), so it costs the schedule nothing, and it is the
    record of what the reader actually did -- which resetting a card does not
    make untrue. ``lookup_count`` and ``last_looked_up_at`` stay for the same
    reason: how often a word had to be looked up again is a fact about the
    reading, not a level to be cleared.

    ``introduced_on`` is cleared, which is the part with a consequence: the card
    goes back to waiting on the daily new-card quota rather than being due at
    once. That is the point -- a reset card is met again, and meeting cards is
    what the quota paces.
    """
    card = session.get(LearningCard, card_id)
    if card is None:
        return False

    fresh = scheduler.new_card(now=datetime.now(timezone.utc))
    card.state = fresh.state.value
    card.learning_step = fresh.learning_step
    card.ladder_stage = fresh.stage
    card.previous_stage = fresh.previous_stage
    card.due_at = fresh.due_at
    card.introduced_on = None
    session.commit()
    return True


def record_lookup(session: Session, card_id: int) -> bool:
    """Note that the reader looked this word up again; report whether it exists.

    The one clean forgetting signal this system gets: the reader just proved
    they had not retained it. **``due_at`` is deliberately untouched** — a
    lookup is not an answer, and the scheduler moves on answers.
    """
    result = session.execute(
        update_stmt(LearningCard)
        .where(LearningCard.id == card_id)
        .values(
            lookup_count=LearningCard.lookup_count + 1,
            last_looked_up_at=func.now(),
        )
    )
    session.commit()
    return result.rowcount > 0
