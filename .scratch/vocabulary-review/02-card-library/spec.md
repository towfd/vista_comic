Status: ready-for-agent

# Vocabulary stage 2: a workshop for the deck, and the end of 歷史紀錄

Stage 2 of `.scratch/vocabulary-review/prd.md`. Stage 1 (`../01-card-storage/`) built the deck
and filled it; this gives the reader somewhere to fix it, and finally removes the tab it
replaces.

## Problem Statement

The deck has no screen. Cards can be created and recognised, and nothing else — a wrong
translation stays wrong, and a word added by a mis-tap stays in the deck for good. Stage 3 will
start quizzing on whatever is in there, so the cost of a bad card is about to go up from
"slightly annoying" to "the app repeatedly teaching you something false".

**What this screen is, and is not.** It is a **workshop**: somewhere to delete mistakes and
correct translations. Seeing familiarity and lookup counts is a small pleasure on top, not the
reason it exists.

That distinction is load-bearing, because a browsable list of collected things is *exactly*
what has failed twice here. 單字本 was deleted on the recorded premise that saved vocabulary is
rarely revisited; 歷史紀錄 replaced it and went unused. **Rarely visiting a workshop is
success, not failure** — it means nothing is broken. Building this as a display case and hoping
for engagement would be the third run at the same wrong bet.

歷史紀錄 also goes here rather than in stage 5. The developer confirmed it is "驗證過的不需要的
功能", this ticket already reshapes that part of the tab bar, and leaving it would mean weeks of
carrying two tabs — one dead, one its replacement — and then editing the tab bar twice.

## Solution

1. A **單字庫** tab, in the slot 歷史紀錄 currently occupies.
2. Cards **grouped by familiarity**, with search across source text and translation.
3. **Edit the translation and the kind. Delete the card.** Nothing else is editable.
4. Jump back to the page a card came from.
5. `Features/History/` removed.

## User Stories

- As a reader who just mis-tapped, I open 單字庫, find the word at the top of the list, and
  delete it.
- As a reader who spots a bad translation weeks later, I search for the word and correct it,
  and the deck stops teaching me something wrong.
- As a reader on a train, I can still look through what I have collected, and the app tells me
  plainly that fixing it needs a connection rather than silently failing.
- As a reader who wonders where a word came from, I jump from the card to the page it was on.

## Implementation Decisions

### Only the translation and the kind are editable

Stage 1 ticket 06 lets the reader declare at collection time whether a line is a word or a
sentence, and that declaration decides which questions stage 3 asks and whether stage 4
generates a sentence for it. Two adjacent buttons means mis-taps, and re-collecting deliberately
does **not** overwrite the kind — so this screen is the only place it can be corrected.

Cards collected before that column existed have no kind at all, and setting them is the other
reason this control exists.

The card's identity is its normalised key plus target language, under a unique constraint
(`../01-card-storage/spec.md`). Editing the source text would change that identity: it could
collide with another card, and it would detach the card from the `comic_id` / `chapter_id` /
`page_number` still pointing at where that exact line was read.

The translation is also **the half that is actually wrong**. The source text was corrected by
the reader before anything else happened; the translation is the part they never fully trusted,
which is why collecting is manual in the first place. A wrong source text means the card was
wrong from the start, and deleting and re-collecting is both cleaner and cheap — one more
selection.

### Delete, and no archive

Archiving was considered and dropped, on the developer's own reasoning: **a word at the top
rung of stage 3's ladder is already scheduled once every 60 days**, which is what "I know this
one, stop testing me" was going to mean. A second concept expressing the same thing would have
had no visible difference in stage 2 and no separate consumer in stage 3.

`archived_at` stays in the schema, unused, exactly as stage 1 left it.

*Recorded for stage 3*: the top rung is 60 days, not never. If a word ever needs to genuinely
retire, that is a rung on the ladder, not an archive flag bolted on afterwards.

### The list is grouped by familiarity, and has search

Grouped by ladder stage, with search over source text and translation.

**Until stage 3 ships there is exactly one group**, holding every card: `ladder_stage` is
written as 0 by stage 1 and nothing advances it yet. The grouping is built now so it fills in
by itself when scheduling arrives; it must degrade to a single unremarkable section rather than
rendering four empty headers.

Search is the workshop's real entrance — "I remember one of these being translated oddly" is
answered by search, and by nothing else once the deck outgrows a screenful.

### Offline: browse yes, change no

The list reads through the repository, falling back to the deck snapshot when the network is
unreachable — the same shape `OfflineFallbackComicRepository` uses for the catalog, and the
snapshot ticket 03 already maintains.

Editing and deleting **require a connection**, and say so plainly when there isn't one.

This is deliberately narrower than stage 1's collecting, and the reason is not effort. Every
queue stage 1 built only ever **adds**. Delete and edit are the first operations that can
*cancel each other out*: a card deleted offline and then re-collected offline has no obvious
correct outcome, and the rule for it would be invented rather than derived. Against that, the
thing given up is editing a translation on a plane — a situation that does not happen, because
noticing a bad translation happens while reading, and reading a downloaded chapter is exactly
when the reader is not also proofreading their deck.

### The peek route has to survive the deletion

Jumping from a card back to the page it came from is wanted here, and that navigation currently
lives in `Features/History/ComprehensionSummary.swift` — inside the folder this ticket deletes.

It must be moved out first, into somewhere shared, and the deletion done afterwards. Deleting
the folder wholesale and re-implementing the route would be the easy mistake, and the reader
would lose a working piece of navigation to a refactor.

### The backend grows two routes

First backend change since stage 1:

```
PATCH  /cards/{id}   -> body {translation}; 200 with the updated card, 404 if unknown
DELETE /cards/{id}   -> 204, 404 if unknown
```

`PATCH` accepts **only** `translation` and `kind`. Source text, target language and the source
reference are not patchable — not because a client would misuse them, but because a field that is
accepted and then changes the row's identity is a trap for the next person, and the state
machine belongs on the server.

Both follow `comprehension_store`'s shape, and both invalidate the deck snapshot: the screen
refreshes after either, so the already-collected marker cannot go on answering from a card that
no longer exists or a translation that has been fixed.

### Removing 歷史紀錄

`Features/History/` (1,089 lines), its tests, and the `RootTabView` entry. The unread
explanation badge goes with it.

**Accepted cost, recorded in the PRD and repeated here so it is not later filed as a bug**: a
deep explanation that fails after its sheet is dismissed can no longer be retried, because
`ComprehensionDetailView` was the only retry path outside the sheet. Re-selecting the line and
asking again costs one of 300 daily requests.

`comprehension_record` and its endpoints are **not** touched. Explanations still work, still
write rows, and stage 4 reads those rows to build its vocabulary breakdown. Only the browsing
screen goes.

## Testing Decisions

Backend (pytest):

- `PATCH` updates the translation, the kind, or both, and returns the card; unknown id is 404.
- `PATCH` accepts a null kind, so a classification can be cleared as well as set.
- An unrecognised kind is rejected rather than stored.
- `PATCH` cannot change source text, key, target language or source reference.
- `DELETE` removes the row and returns 204; unknown id is 404; deleting twice is 404 the second
  time.
- A deleted card can be collected again afterwards, as a new card.

iOS (`vista_comicTests`):

- Grouping: cards land in the right sections; a deck all on one rung renders one section, not
  four with three empty.
- Search: matches source text, matches translation, is case- and width-insensitive (it should
  reuse the normalisation the deck already agrees on rather than inventing a second rule),
  empty query shows everything.
- The list falls back to the snapshot when the fetch fails, and reports the failure without
  losing what it can already show.
- Edit and delete are refused offline, and say so.
- The snapshot is refreshed after a successful edit or delete.

**No XCUITest is written, built, or run.** UI verification is handed over as a checklist:
sections on both phone sizes, search with no matches, the empty deck, a failed edit, deleting
the last card, and confirming 歷史紀錄 is gone with the reader's own explanations still
arriving in the reader sheet.

## Out of Scope

- Any lesson, question, or scheduling behaviour (stage 3).
- Archiving, and any notion of retiring a word.
- Editing the source text, target language, or source reference.
- Inferring a kind for the cards that predate it. They are shown as unclassified and set by hand, because guessing is what ticket 06 exists to avoid.
- Offline editing and deleting.
- Bulk selection and bulk delete. Worth revisiting only once the deck is large enough to make
  one-at-a-time painful, which is a fact to observe rather than predict.
- Sorting controls. The grouping plus search covers both routes the developer described; a
  third way in would be furniture.
- Removing `comprehension_record`, its endpoints, or the explanation flow.

## Further Notes

The screen most likely to be judged a failure by how rarely it is opened is this one. It should
not be. The measure that matters here is whether a bad card can be found and fixed in under a
minute when the reader goes looking — not how often they go.
