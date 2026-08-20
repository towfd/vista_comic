# 03 — 單字庫 takes the tab, and 歷史紀錄 goes

**What to build:** A **單字庫** tab in the slot 歷史紀錄 occupies today, listing the deck grouped by familiarity with a search field — and `Features/History/` removed in the same change.

The two halves are one ticket on purpose: the tab bar is edited once, and there is never a build where the reader has both a dead tab and its replacement.

**Read-only.** Editing and deleting are ticket 04. This one is worth having on its own because it answers the question the workshop rests on — *can a card be found* — before anything can act on what is found.

## The list

Grouped by ladder stage, with a search field over source text and translation.

**Until stage 3 ships there is exactly one group**, holding everything: `ladder_stage` is written as 0 by stage 1 and nothing advances it yet. The grouping must render as one unremarkable section — not four headers with three of them empty — and fill in by itself when scheduling arrives.

Search should reuse the normalisation the deck already agrees on (`TextNormalization.swift`) rather than inventing a second matching rule. There is one definition of "the same text" in this app and it should stay that way.

Each row shows the source text, the translation, which comic it came from, its familiarity and its lookup count. Cards with no kind are marked as unclassified — ticket 04 is where that gets fixed, and the reader needs to be able to see which ones need it.

## The backend has to join the comic title

**Found while implementing ticket 02, and not visible when this ticket was written.**

`LearningCardResponse` carries `comicId` and `chapterId` but no titles, and this ticket needs
them twice over:

- A row is supposed to show which comic a card came from, and an id is a key, not a label.
- **Whether jumping back can work at all is decided by the title, not by the ids.** A `nil`
  comic title is the backend saying that comic has left the library; the stored ids would still
  build a route, and that route would fail. Without the join, the screen can only offer a jump
  that sometimes breaks.

So `GET /cards` gains `comicTitle` and `chapterTitle`, joined from the in-memory catalog at read
time exactly as `/comprehensions` already does — `main._titles_for` is the existing function and
should be reused rather than copied. Titles are decoration and the cards are the data, so a
missing catalog degrades the labels rather than failing the request, which is the rule that
function already follows.

This also means the deck snapshot starts carrying titles, which is free.

## Offline

The list reads through the repository and falls back to the deck snapshot when the network is unreachable, the shape `OfflineFallbackComicRepository` already uses. A reader on a train can look through everything they have collected.

## Removing 歷史紀錄

`Features/History/` (1,089 lines), its tests, the `RootTabView` entry, and the unread explanation badge.

**Accepted cost, recorded so it is not later filed as a bug:** a deep explanation that fails after its sheet is dismissed can no longer be retried, because `ComprehensionDetailView` was the only retry path outside the sheet. Re-selecting the line and asking again costs one of 300 daily requests.

`comprehension_record` and its endpoints are **not** touched. Explanations still work, still write rows, and stage 4 reads those rows. Only the browsing screen goes.

**Blocked by:** 02 — Free the jump-to-source route from 歷史紀錄.

**Status:** done — backend `226 passed`, iOS exit 0 with zero failures, and **device-verified by the repo owner, 2026-08-20**. The tab bar is 書庫 / 已下載 / Vocabulary; 歷史紀錄 is gone.

- [x] A 單字庫 tab replaces 歷史紀錄; the tab bar still has three tabs
- [x] Cards are grouped by familiarity, and a deck all on one rung renders one section rather than several empty ones
- [x] Search matches source text and translation, and uses the deck's existing normalisation rather than a second rule
- [x] Search with no matches says so, distinctly from an empty deck
- [x] An empty deck says something useful about how to fill it
- [x] `GET /cards` returns `comicTitle` and `chapterTitle`, joined at read time by the existing `_titles_for`
- [x] A card whose comic has left the library returns null titles rather than failing
- [x] Each row shows source, translation, source comic, familiarity and lookup count
- [x] A card whose comic is gone shows the jump as unavailable rather than offering one that fails
- [x] Cards with no kind are visibly unclassified
- [x] Tapping a row jumps to the page it came from, using the route moved in ticket 02
- [x] With no connection the list still renders from the snapshot, and says the data may be stale rather than pretending otherwise
- [x] `Features/History/` and its tests are gone, and nothing else imports them
- [x] Asking for an explanation still works, and still writes a record
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- Backend: `GET /cards` now carries `comicTitle`/`chapterTitle`, joined at read time by the existing `_titles_for`, with the same degradation — an unavailable catalog costs the labels, not the request.
- `Features/Study/CardLibrary.swift` — `Familiarity`, `groupedByFamiliarity`, `cardsMatching`, and `LearningCard.source`/`sourceLabel`. Free functions, testable without rendering.
- `Features/Study/StudyView.swift` and `components/CardRow.swift`.
- `RootTabView` — 單字庫 in 歷史紀錄's slot; still three tabs.
- `Features/History/` deleted (1,089 lines), with its unit tests, its UI tests, and the unread badge.

**Three decisions worth review:**

1. **A single band gets no heading.** Every card sits in `New` until stage 3 ships, and a header above a list where every row says the same thing is furniture. Bands appear by themselves as cards reach them.
2. **Search reuses `normalizedKey`** rather than a second matching rule. There is one definition of "the same text" in this app — the one the deck's identity is built on — and a search that disagreed with it would find nothing for a word the reader can plainly see.
3. **A card whose comic has left the library is shown without a link**, not as a link that fails. One signal (`comicTitle == nil`) withdraws both the label and the jump.

Offline, the list falls back to the deck snapshot and says so. It is only a `failed` state when nothing is cached either — showing the reader their own vocabulary beats showing them an error about it.

## A consequence the spec did not record

Removing 歷史紀錄 also removed `UnreadExplanationBadge`, which the selection sheet handed its
record to on dismissal. **So an explanation that arrives after the sheet is closed is now
written, charged against the daily cap, and unobservable.**

The spec recorded only that a *failed* explanation can no longer be retried. This is broader:
深入解釋 changes from "ask and come back later" to "ask and wait", and waiting was exactly what
the asynchronous design existed to avoid.

Reported to the repo owner rather than absorbed silently. Three options were put to them: accept
it (waiting is what happens in practice anyway, and it stops forgotten requests burning quota);
keep 歷史紀錄 after all; or attach the explanation to the card, for which
`learning_card.comprehension_record_id` already exists and is always NULL.

**Decision, 2026-08-20: accepted.** 深入解釋 is an "ask and wait" action from here. Attaching
explanations to cards stays available as stage 4 work if waiting turns out to be a nuisance in
practice, and the foreign key is already in place for it.

## Device checklist for the repo owner

1. The tab bar reads **書庫 / 已下載 / Vocabulary**, still three tabs, and 歷史紀錄 is gone.
2. Vocabulary lists every card, newest first, with **no section header** — everything is on rung 0 today, and one heading above one list would be noise.
3. Each row shows the source text, translation, which comic it came from, and a re-lookup count where one exists. The cards collected before ticket 06 show as **Unclassified**.
4. Search a word in the source text, then search part of a **translation** — both find it. Search something absent: it says "no results", worded differently from an empty deck.
5. Tap a row: it opens the page that line came from, and **leaving does not change where you were actually reading** (it is a peek).
6. Airplane mode, open the tab: the list still renders and says it is showing what was saved on this device.
7. Ask for a 深入解釋 and **stay on the sheet**: it still arrives and reads exactly as before. The record is still written — only the browsing screen is gone.
8. Both phone sizes: rows do not truncate awkwardly, and the search field behaves.
