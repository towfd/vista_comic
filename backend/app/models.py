"""API response models.

Field names are camelCase to match the iOS contract (``Shared/Models.swift``)
and the API shapes in ``docs/backend-architecture.md`` exactly, so the JSON is
decoded 1:1 by the app.

Internal catalog dataclasses (with page paths, used by later slices) are kept
separate from the response models so we only expose contract fields.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional

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
# Saved-translation endpoint models (ocr-translation ticket 02, "單字本").
# ---------------------------------------------------------------------------


class SavedTranslationCreate(BaseModel):
    """Request body for ``POST /translations``.

    ``comicId`` / ``chapterId`` are the catalog's stable IDs; ``pageNumber`` is
    the same 1-based Page index used by the reader and ``Progress.lastPage``.
    """

    originalText: str
    translatedText: str
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int = Field(ge=1)


class SavedTranslationResponse(BaseModel):
    """One saved translation: the response for ``POST /translations`` (echoes
    the saved state) and each item of ``GET /translations``.
    """

    id: int
    originalText: str
    translatedText: str
    targetLanguage: str
    comicId: str
    chapterId: str
    pageNumber: int
    savedAt: str  # ISO-8601 UTC


# ---------------------------------------------------------------------------
# Comprehension endpoint models (llm-comprehension ticket 11).
# ---------------------------------------------------------------------------


class ComprehendRequest(BaseModel):
    """Request body for ``POST /comprehend``.

    ``sourceText`` is the (possibly user-corrected) OCR reading shown on
    screen -- ground truth sent explicitly so Claude translates/explains it
    rather than re-deriving its own reading from the images; the images are
    for visual context only. ``useStrongerModel`` selects Claude Sonnet 5
    instead of the default Claude Haiku 4.5 (the manual-upgrade path wired up
    end-to-end in a later ticket; the field must exist now).
    """

    cropImageBase64: str
    pageImageBase64: str
    sourceText: str
    targetLanguageCode: str
    useStrongerModel: bool = False


class ComprehendResponse(BaseModel):
    """Response for ``POST /comprehend``.

    Always HTTP 200; ``status`` discriminates a genuine success (``"ok"``,
    all four explanation fields present) from a model-declined outcome
    (``"declined"``, fields omitted). The route uses
    ``response_model_exclude_none`` so a declined response body is exactly
    ``{"status": "declined"}``. Any other failure (network/API error,
    malformed request) is a normal HTTP 4xx/5xx, never this 200 shape.
    """

    status: str  # "ok" | "declined"
    translation: Optional[str] = None
    grammarNotes: Optional[str] = None
    contextNotes: Optional[str] = None
    toneRegister: Optional[str] = None
