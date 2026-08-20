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

**Status:** not started.

- [ ] The translation can be edited and the change persists
- [ ] The kind can be set, changed, and cleared, including on cards that never had one
- [ ] There is no way to edit the source text, target language, or source reference from this screen
- [ ] A card can be deleted, and deleting is confirmed first — it is the one irreversible action here
- [ ] After deleting, the card is gone from the list without a manual refresh
- [ ] After either action the deck snapshot is refreshed, so the already-collected marker cannot answer from stale data
- [ ] After deleting a card, re-collecting that line in the reader creates a new card and the marker behaves accordingly
- [ ] Offline, both actions are refused with an explanation rather than failing silently or appearing to succeed
- [ ] A failed edit leaves the original text on screen rather than discarding what was typed
- [ ] Editing to an empty translation is refused
- [ ] No XCUITest is written; a device checklist is handed to the repo owner
