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

**Status:** not started.

- [ ] A 單字庫 tab replaces 歷史紀錄; the tab bar still has three tabs
- [ ] Cards are grouped by familiarity, and a deck all on one rung renders one section rather than several empty ones
- [ ] Search matches source text and translation, and uses the deck's existing normalisation rather than a second rule
- [ ] Search with no matches says so, distinctly from an empty deck
- [ ] An empty deck says something useful about how to fill it
- [ ] `GET /cards` returns `comicTitle` and `chapterTitle`, joined at read time by the existing `_titles_for`
- [ ] A card whose comic has left the library returns null titles rather than failing
- [ ] Each row shows source, translation, source comic, familiarity and lookup count
- [ ] A card whose comic is gone shows the jump as unavailable rather than offering one that fails
- [ ] Cards with no kind are visibly unclassified
- [ ] Tapping a row jumps to the page it came from, using the route moved in ticket 02
- [ ] With no connection the list still renders from the snapshot, and says the data may be stale rather than pretending otherwise
- [ ] `Features/History/` and its tests are gone, and nothing else imports them
- [ ] Asking for an explanation still works, and still writes a record
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
