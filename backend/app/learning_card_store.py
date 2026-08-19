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

from datetime import date, datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import LearningCard
from .normalization import normalized_key

# Where a new card starts on stage 3's interval ladder. Written now, read there.
INITIAL_LADDER_STAGE = 0

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
    today: Optional[date] = None,
) -> Tuple[LearningCard, bool]:
    """Collect ``source_text``; return the card and whether it was new.

    **Idempotent on the card's identity**, rather than conflicting. The app's
    offline queue replays whatever it could not send, blindly and possibly more
    than once, and a replay must not be an error — so an existing card comes
    back with ``created=False`` and the endpoint answers 200 instead of 409.

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
        ladder_stage=INITIAL_LADDER_STAGE,
        due_on=today or datetime.now(timezone.utc).date(),
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


def record_lookup(session: Session, card_id: int) -> bool:
    """Note that the reader looked this word up again; report whether it exists.

    The one clean forgetting signal this system gets: the reader just proved
    they had not retained it. **``due_on`` is deliberately untouched** —
    rescheduling on a hit belongs to stage 3, where scheduling exists at all.
    """
    result = session.execute(
        update(LearningCard)
        .where(LearningCard.id == card_id)
        .values(
            lookup_count=LearningCard.lookup_count + 1,
            last_looked_up_at=func.now(),
        )
    )
    session.commit()
    return result.rowcount > 0
