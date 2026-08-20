"""API response models.

Field names are camelCase to match the iOS contract (``Shared/Models.swift``)
and the API shapes in ``docs/backend-architecture.md`` exactly, so the JSON is
decoded 1:1 by the app.

Internal catalog dataclasses (with page paths, used by later slices) are kept
separate from the response models so we only expose contract fields.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import List, Literal, Optional

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Internal in-memory catalog (source of truth held in memory after a scan).
# Not serialized directly; response models are projected from these.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ChapterEntry:
    id: str
    number: int
    title: str
    # Relative POSIX page paths under the library root, in reading order.
    # Held now for Slice 2 (reader + /media); not exposed in Slice 1 JSON.
    page_paths: List[str] = field(default_factory=list)
    # Relative POSIX path of this chapter's own ``cover.*``, or None when it has
    # none. Deliberately NOT one of ``page_paths``: a cover is something to
    # recognise the chapter by, not something to read, so it is excluded from
    # the reading order and from ``page_count``.
    cover_path: Optional[str] = None

    @property
    def page_count(self) -> int:
        return len(self.page_paths)


@dataclass(frozen=True)
class ComicEntry:
    id: str
    title: str
    # Relative POSIX path of the resolved cover image under the library root,
    # or None if the comic has no pages at all (then it is skipped upstream).
    cover_path: Optional[str]
    chapters: List[ChapterEntry] = field(default_factory=list)

    @property
    def chapter_count(self) -> int:
        return len(self.chapters)


# ---------------------------------------------------------------------------
# Response models (camelCase, contract-facing).
# ---------------------------------------------------------------------------


class ChapterSummary(BaseModel):
    id: str
    number: int
    title: str
    pageCount: int
    # This chapter's own first page, so the chapter list can show what the
    # chapter actually looks like instead of one shared placeholder. Absolute,
    # like every other media URL here -- the app never builds these itself.
    coverUrl: str
    # Derived live from the progress store (Slice 4): "unread" | "reading" | "read".
    readState: str


class ComicSummary(BaseModel):
    """One entry in ``GET /comics``."""

    id: str
    title: str
    coverUrl: str
    chapterCount: int
    lastReadAt: Optional[str] = None  # null in v1 (folder has no such value)
    # The chapter the reader should open for "Continue" — always present (every
    # comic has >= 1 chapter). Selection is derived live from the progress store;
    # see docs/backend-architecture.md and progress_store.continue_chapter_id.
    continueChapterId: str


class ComicDetail(BaseModel):
    """Response for ``GET /comics/{comicId}``."""

    id: str
    title: str
    coverUrl: str
    chapters: List[ChapterSummary]


class ChapterDetail(BaseModel):
    """Response for ``GET /comics/{comicId}/chapters/{chapterId}``.

    ``pages`` are absolute image URLs in reading order; the app fetches each as
    an image. See ``docs/backend-architecture.md`` (reader endpoint).
    """

    id: str
    number: int
    title: str
    pages: List[str]
    # 1-based resume position from the progress store; omitted when no progress
    # (the route uses response_model_exclude_none). See Slice 4 contract.
    lastReadPage: Optional[int] = None


# ---------------------------------------------------------------------------
# Reading-progress endpoint models (Slice 4).
# ---------------------------------------------------------------------------


class ProgressUpdate(BaseModel):
    """Request body for ``PUT .../progress``: a 1-based page position."""

    lastPage: int


class ProgressResponse(BaseModel):
    """Response for ``PUT .../progress`` (echoes the saved state)."""

    comicId: str
    chapterId: str
    lastPage: int
    pageCount: int
    updatedAt: str  # ISO-8601 UTC


# ---------------------------------------------------------------------------
# Comprehension record models (comprehension-response-ux, the 歷史紀錄 store).
# ---------------------------------------------------------------------------


class ComprehensionRecordCreate(BaseModel):
    """Request body for ``POST /comprehensions``.

    Carries no images. The worker re-reads the page from the library on disk
    using ``comicId``/``chapterId``/``pageNumber``, so nothing image-shaped has
    to be uploaded or stored -- and this request stays small enough to return
    instantly, which is its whole purpose.

    ``translatedText`` is the *on-device* translation the reader is already
    looking at by the time this is sent; the cloud's own translation arrives
    later on the record.
    """

    sourceText: str
    translatedText: str
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int = Field(ge=1)
    useStrongerModel: bool = False


class ComprehensionRecordResponse(BaseModel):
    """One comprehension record, as returned by every ``/comprehensions`` route.

    ``status`` is the single discriminator (``pending``/``running``/``ok``/
    ``declined``/``failed``) -- clients must not infer state from which
    explanation fields happen to be null.

    ``comicTitle``/``chapterTitle`` are joined from the in-memory catalog at
    read time rather than stored: the record only holds path-hash ids, which are
    fine as keys and unusable as labels on a browsable list. They are ``None``
    when the comic is no longer in the library, which is also the client's cue
    to disable jump-to-source for that row.
    """

    id: int
    sourceText: str
    translatedText: str
    cloudTranslation: Optional[str] = None
    grammarNotes: Optional[str] = None
    contextNotes: Optional[str] = None
    toneRegister: Optional[str] = None
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int
    comicTitle: Optional[str] = None
    chapterTitle: Optional[str] = None
    status: str
    isRead: bool
    useStrongerModel: bool
    createdAt: str  # ISO-8601 UTC


class LearningCardCreate(BaseModel):
    """Request body for ``POST /cards``.

    ``translation`` is whatever the reader was looking at when they pressed add
    -- the on-device wording if they added straight after translating, Claude's
    if they waited for an explanation first. The server does not judge which:
    the stored translation is the one the reader read and approved, and that
    approval is the whole quality gate.

    ``sourceText`` is capped rather than unbounded so a stray whole-page
    selection cannot become a card. Text that normalises to nothing is refused
    by the route, which the length cap alone cannot catch.
    """

    sourceText: str = Field(min_length=1, max_length=200)
    translation: str
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int = Field(ge=1)
    # Which of the two save buttons the reader pressed. Optional so a client
    # that predates the buttons still works, and constrained so an unrecognised
    # value is refused here rather than reaching stage 3 as a card no question
    # type knows what to do with.
    kind: Optional[Literal["word", "sentence"]] = None


class LearningCardResponse(BaseModel):
    """One collected card, as returned by every ``/cards`` route.

    ``ladderStage`` and ``dueOn`` are carried from the first release even though
    nothing reads them until stage 3: the app caches this response wholesale as
    its deck snapshot, and a field added later would mean every cached snapshot
    predating it is missing one.

    ``lookupCount`` counts only times the reader looked this word up *again*.
    Its absence means nothing -- see ``db.LearningCard``.

    ``kind`` is ``None`` for cards collected before the reader could say, and
    for those it stays ``None`` until they say so in 單字庫. It is never
    guessed.

    ``comicTitle``/``chapterTitle`` are joined from the in-memory catalog at
    read time rather than stored, exactly as ``ComprehensionRecordResponse``
    does: the card holds path-hash ids, which are correct as keys and useless as
    labels. A ``None`` comic title is also the client's cue that jumping back to
    the page would fail, because the join is what proves the comic is still in
    the library.
    """

    id: int
    sourceText: str
    translation: str
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int
    comicTitle: Optional[str] = None
    chapterTitle: Optional[str] = None
    kind: Optional[str] = None
    ladderStage: int
    dueOn: str  # ISO-8601 date
    lookupCount: int
    lastLookedUpAt: Optional[str] = None  # ISO-8601 UTC
    createdAt: str  # ISO-8601 UTC


class LearningCardUpdate(BaseModel):
    """Request body for ``PATCH /cards/{id}``.

    **Exactly two fields, and refusing the rest is the point.** ``sourceText``
    is half the card's identity and ``targetLanguage`` is the other half;
    changing either could collide with another card under the unique constraint,
    and changing the source would detach the row from the
    ``comicId``/``chapterId``/``pageNumber`` still pointing at where that exact
    line was read. The source reference is a fact about the past. A field that
    is accepted and then quietly changes which card this *is* would be a trap
    for whoever touches this next.

    **A null ``kind`` is a value, not an omission.** Cards collected before the
    two save buttons existed have none, and the reader must be able to clear a
    wrong answer as well as set one -- so the route reads ``model_fields_set``
    rather than testing for ``None``. This is the one place in this feature
    where "absent" and "present and null" mean different things.
    """

    translation: Optional[str] = Field(default=None, min_length=1)
    kind: Optional[Literal["word", "sentence"]] = None


class CardReviewCreate(BaseModel):
    """Request body for ``POST /cards/{id}/reviews``.

    ``clientToken`` is generated by the app, one per answer, and is what makes a
    resubmission idempotent. A tapped button on a slow connection is exactly how
    one answer becomes two, and a duplicated wrong answer would drop a rung the
    reader never lost.

    ``elapsedMs`` is optional and read by nothing today. The review log is kept
    complete so that swapping the fixed ladder for FSRS later is an algorithm
    change rather than a data migration -- and response time cannot be collected
    retroactively.
    """

    questionType: Literal["cloze_choice", "cloze_typed"]
    isCorrect: bool
    clientToken: str = Field(min_length=1, max_length=100)
    elapsedMs: Optional[int] = Field(default=None, ge=0)
    # The **reader's** local date, not the server's. The daily spend cap resets
    # on UTC because a budget wants a consistent moment; a practice day wants
    # midnight where the reader is. On UTC+8 a UTC boundary would reset their
    # day at eight in the morning, so a card passed before breakfast could be
    # passed again after it and climb two rungs in one felt day.
    localDate: date


class CardReviewResponse(BaseModel):
    """One recorded answer, and nothing about the card.

    Deliberately lean. A step or a rung on this row would be describing the
    *card* rather than the answer, and would be meaningless on a row from last
    week — see ``ReviewOutcome`` for where those belong.
    """

    id: int
    cardId: int
    questionType: str
    isCorrect: bool
    elapsedMs: Optional[int] = None
    reviewedAt: str  # ISO-8601 UTC


class ReviewOutcome(BaseModel):
    """What recording an answer changed.

    Returned only by ``POST``, because these are facts about the card *now*:
    they answer "what did that do", which only the answer just given can ask.
    The app is told rather than left to derive it, so the two sides can never
    disagree about whether a rung moved.
    """

    review: CardReviewResponse
    #: Where the card stands today — unseen / unfamiliar / familiar / passed.
    #: Derived from the day's answers, never stored.
    step: str
    ladderStage: int
    dueOn: str
    #: Whether this answer was the one that moved the rung. False for every
    #: answer after the day's first resolution, which is how "at most once per
    #: day" is visible to the app rather than inferred.
    ladderMoved: bool


class ComprehensionRecordReadUpdate(BaseModel):
    """Request body for ``PATCH /comprehensions/{id}``.

    Only the read flag is patchable. Status transitions are deliberately not
    exposed -- re-running a record is its own endpoint with its own precondition
    and its own cap reservation, so the state machine stays server-side.
    """

    isRead: bool
