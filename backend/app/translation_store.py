"""Repository for the saved-translation store ("單字本").

Thin functions over a SQLAlchemy ``Session``, mirroring ``progress_store.py``'s
plain-function-over-a-session shape (no repository class).

Unlike ``progress_store``, there are no ``safe_*`` degrade-to-default read
wrappers here. The catalog reads degrade gracefully because the Library folder
is an independent source of truth the app can still browse during a DB outage
(see ``progress_store``'s module docstring). Saved translations have no such
independent origin -- the ``saved_translation`` table *is* the data -- so both
the write and the list read surface a failure to the caller (503 in
``main.py``) instead of silently returning an empty list, which would
misrepresent "the store is unreachable" as "nothing has been saved".
"""

from __future__ import annotations

from typing import List

from sqlalchemy import func, insert, select
from sqlalchemy.orm import Session

from .db import SavedTranslation


def insert_translation(
    session: Session,
    *,
    original_text: str,
    translated_text: str,
    target_language: str,
    comic_id: str,
    chapter_id: str,
    page_number: int,
) -> SavedTranslation:
    """Insert one saved-translation row; return it with ``id``/``saved_at`` filled in.

    ``saved_at`` uses the database clock (``now()``) as the source of truth,
    matching ``progress_store.upsert``'s ``updated_at`` convention. Returns a
    plain (session-detached) ``SavedTranslation`` built from the caller's
    values plus the two DB-generated columns, so the endpoint can echo the
    saved state without a second round trip.
    """
    stmt = (
        insert(SavedTranslation)
        .values(
            original_text=original_text,
            translated_text=translated_text,
            target_language=target_language,
            comic_id=comic_id,
            chapter_id=chapter_id,
            page_number=page_number,
            saved_at=func.now(),
        )
        .returning(SavedTranslation.id, SavedTranslation.saved_at)
    )
    generated = session.execute(stmt).one()
    session.commit()
    return SavedTranslation(
        id=generated.id,
        original_text=original_text,
        translated_text=translated_text,
        target_language=target_language,
        comic_id=comic_id,
        chapter_id=chapter_id,
        page_number=page_number,
        saved_at=generated.saved_at,
    )


def list_all(session: Session) -> List[SavedTranslation]:
    """Every saved translation, most recently saved first."""
    rows = session.execute(
        select(SavedTranslation).order_by(SavedTranslation.saved_at.desc())
    ).scalars()
    return list(rows)
