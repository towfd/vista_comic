# 04 — Fix a card

**What to build:** The two actions the workshop exists for — correct a card, or throw it away.

- **Edit the translation.** The half that can be wrong, and the reason this screen exists at all: the source text was corrected by the reader before anything else happened, but the translation is the part they never fully trusted.
- **Edit the kind.** Two adjacent save buttons will be mis-tapped, and re-collecting deliberately does not overwrite the kind, so this is the only place a wrong answer can be corrected. It is also where the cards that predate ticket 06 get classified.
- **Delete the card.**

**Nothing else is editable**, and the reasons are on the routes in ticket 01. A wrong source text means the card was wrong from the start; deleting and re-collecting is cleaner and costs one more selection.

**Editing and deleting require a connection**, and say so plainly when there is none.

This is narrower than stage 1's collecting, and the reason is not effort. Every queue stage 1 built only ever **adds**. Delete and edit are the first operations that can cancel each other out — a card deleted offline and then re-collected offline has no obviously correct outcome, and the rule for it would be invented rather than derived. What is given up is editing a translation on a plane, which does not happen: noticing a bad translation happens while reading, and reading a downloaded chapter is exactly when the reader is not also proofreading their deck.

**Deleting must not leave the marker lying.** The deck snapshot has to be refreshed after either action, or the already-collected marker goes on answering from a card that no longer exists, or shows a translation that has been fixed.

**Blocked by:** 01 — Edit and delete on the backend; 03 — 單字庫 takes the tab.

**Status:** implemented on branch `feat/deck-lookup-marker`, 2026-08-20. **Awaiting the repo owner's device pass** (checklist below).

- [x] The translation can be edited and the change persists
- [x] The kind can be set, changed, and cleared, including on cards that never had one
- [x] There is no way to edit the source text, target language, or source reference from this screen
- [x] A card can be deleted, and deleting is confirmed first — it is the one irreversible action here
- [x] After deleting, the card is gone from the list without a manual refresh
- [x] After either action the deck snapshot is refreshed, so the already-collected marker cannot answer from stale data
- [x] After deleting a card, re-collecting that line in the reader creates a new card and the marker behaves accordingly
- [x] Offline, both actions are refused with an explanation rather than failing silently or appearing to succeed
- [x] A failed edit leaves the original text on screen rather than discarding what was typed
- [x] Editing to an empty translation is refused
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `StudyRepository.update(id:translation:kind:)` and `delete(id:)`, implemented in `APIStudyRepository` against ticket 01's routes and passed straight through by the offline decorator.
- `Features/Study/CardDetailView.swift` — the form.
- `StudyView` now navigates to the card rather than to the page, and swaps or drops a row in place afterwards.

**Four decisions worth review:**

1. **Both fields are always sent.** The screen is a form showing both, which sidesteps "did they mean *don't change it* or *set it to nothing*" entirely — the question that made ticket 01's route read `model_fields_set`. A null kind therefore **clears** the classification, which is a thing to want.
2. **Tapping a row opens the card, not the page.** In a workshop the reason to tap something is to work on it; the jump to source is one tap further in, in the detail screen where the source is named.
3. **Neither action is queued when it fails.** Every queue stage 1 built only ever *adds*; these are the first operations that can cancel each other out. Asserted, so that a future "offline delete would be convenient" change fails a test that says why not.
4. **A failed save keeps what was typed.** The reader's correction is the only copy of it, and discarding it to show an error would cost them the work rather than just the save.

Deleting confirms first, and the confirmation names the cost — the lookup count and ladder position go with the row.

## Verification

Two suites of unit tests. The structural one is worth naming: **`update` takes a translation and a kind and nothing else**, so there is no route from this screen to the source text, target language or page reference. That test exists to fail if the signature ever grows, since the failure it guards against is a field silently accepted.

## Device checklist for the repo owner

1. Open 單字庫 and tap a card. It opens the card, **not** the comic page.
2. Change the meaning and Save. The list shows the new meaning **without reloading or scrolling**, and reopening the card shows it stuck.
3. Save is disabled when nothing has changed, and when the meaning is emptied.
4. Set a card's type, change it, then set it to **Unclassified**. All three stick. Your three oldest cards are unclassified and are the ones to try this on.
5. Tap **Where it came from** — it opens that page, and leaving does **not** change where you were actually reading.
6. **Delete a card.** It confirms first, and the confirmation says the lookup count goes too. After deleting, the row is gone from the list with no manual refresh.
7. **Delete one of the three duplicate Vietnamese cards**, then re-frame that same line in the reader: it offers to add rather than claiming you already learned it — the marker's snapshot was refreshed.
8. **Airplane mode**: editing and deleting both refuse and say a connection is needed. Nothing appears to succeed, and what you typed is still there.
9. A card whose comic has left the library shows "no longer in your library" instead of a link.
