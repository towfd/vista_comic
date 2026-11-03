Status: ready-for-agent

# Card notes: an optional explanation the reader writes, shown after answering

## Problem Statement

Raised by the repo owner, 2026-11-04. A card holds a source text and a translation, and nothing else the reader can write. When they collect a word or a sentence they often know *why* it matters -- it is colloquial, `đi` here is not "go", it pairs with another word -- and there is nowhere to put that. The translation field is the wrong place: it is what a sentence question asks for, and what the reader approved as the card's meaning.

## Solution

A card has an optional **note**: plain text the reader writes, edits, or clears. It is written when collecting on the web reader or later on the card page, and shown in a session **only after an answer**, in its own section at the bottom of the feedback.

Web and backend only. iOS is unchanged and keeps working (see Compatibility).

## Decisions

Grilled with the owner on 2026-11-04.

| Question | Decision |
|---|---|
| Platforms | Backend and web. iOS deferred; a ticket will be opened when the app is used again. |
| Format | Plain text. Line breaks kept, shown as typed (`whitespace-pre-wrap`). No markdown or links. |
| Length | At most 1000 characters, counted after trimming. |
| Blank | Leading and trailing whitespace is trimmed. A note that trims to nothing is stored as `null`. Clearing the field and saving clears the note. |
| Existing cards | `null`. Nothing is backfilled. |
| Editing | On the card page (`DeckCardView`), under the translation, saved with the same button. |
| Collecting a line already in the deck | The existing card is **not** changed, as today. The 已收藏 notice also shows the existing card's note when it has one, and says the note typed here was not saved when the reader typed one. The typed note stays in the panel so it can be copied to the card page. |
| When it is shown in a session | After the verdict: right, wrong, or 算我對. Never while the question is open, since a note often gives the answer away. |
| Where | Its own section headed 註解, below the 算我對 / 下一題 buttons and above 這張卡片有問題？到字卡庫修改 ↗. Nothing at all is shown for a card with no note. |
| Card library list and search | Neither shows nor searches the note. |

## Wire contract

- `LearningCardResponse.note: string | null`, on every `/cards` route.
- `POST /cards` accepts an optional `note`. It is applied only when the card is created. A `200` (already collected) leaves the existing card's note alone and returns it.
- `PATCH /cards/{id}` accepts `note`. Read from `model_fields_set`, like `kind`: **absent leaves the note alone**, while `null` or blank clears it. A body with only `note` is valid.
- Over 1000 characters after trimming is refused with `422`.

## Compatibility

- **iOS decoding.** `LearningCard.init(from:)` decodes only the keys in its own `CodingKeys` (`vista_comic/vista_comic/Networking/LearningCard.swift:140`), so `note` is ignored. The deck snapshot stores response bytes, not re-encoded cards, so nothing is lost there either.
- **iOS edits.** `APIStudyRepository.update` sends only `translation` and `kind` (`vista_comic/vista_comic/Networking/APIStudyRepository.swift:125`). Because an absent `note` leaves the note alone, editing on the phone never clears a note written on the web.
- **Deploy order.** The backend ships before or with the web. An older backend silently drops an unknown `note` (pydantic ignores extra fields), which would look like a save that worked.

## Out of scope

- iOS: showing, writing, or editing notes.
- Rich text, links, images.
- Notes in the card library list or search.
- Generating notes with Claude.
- Merging a typed note into an already-collected card.
