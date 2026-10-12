# 02 — A line already collected, and a failed save

**What to build:** The two ways an add does not produce a new card each get their own, legible outcome in the panel.

When the line is already in the deck, the panel stays open with what the reader typed and says so, showing the existing card's own text and translation and a link to that card in 字卡庫 — where its translation or kind can be corrected. The existing card's text is shown because the deck's identity ignores spacing and case, so the match may not look identical to what was typed. A card the reader had deleted comes back, and reappears in the held deck.

When the save fails, the panel stays open with both fields as they were and says the card was not saved, distinguishing a sign-in failure from the backend being unreachable. Pressing an add button again is the retry; it is always safe because the backend treats a repeat as the same card.

Either notice clears as soon as the reader edits a field. A response that arrives after the panel was collapsed, or after the chapter changed, never reopens the panel or writes into the new chapter's state — though a card it created still reaches the deck.

No repeat-lookup is recorded for an already-collected line. See [the spec](../spec.md), *A card that already exists* and *When saving fails*.

**Blocked by:** 01 — Collect a card from the reader.

**Status:** ready-for-agent

- [ ] Adding a line already in the deck keeps the panel open and the fields intact, and does not show the added confirmation
- [ ] The notice shows the existing card's source text and translation, and links to that card's page in 字卡庫
- [ ] A previously deleted card collected again is back in 字卡庫 without a reload
- [ ] An existing card keeps its kind when collected under the other button
- [ ] A failed save keeps the panel open and the fields intact, with a message that the card was not saved
- [ ] A sign-in failure is reported differently from an unreachable backend
- [ ] Pressing an add button after a failure retries, and a retry that succeeds behaves exactly as a first-time add
- [ ] Editing either field clears an already-collected or failure notice
- [ ] A response arriving after a collapse or a chapter change does not reopen the panel; a card it created is still in the held deck
- [ ] No lookup is recorded against an already-collected card
- [ ] Unit tests cover each outcome above through the collecting store; the existing web suite still passes
- [ ] The developer is handed the browser checks: the notice and its link for a known line, and a failed add recovering once the backend is back
