Status: ready-for-agent
Blocked by: 01

# 03 — Write a note when collecting

**What to build:** The web reader's collect panel has an optional 註解 field under the translation. It is sent with the card. When the line was already collected, the notice shows the existing card's note and says the typed note was not saved.

**Files (boundary):**
- `web/src/components/CollectPanel.vue`
- `web/src/stores/collect.ts`, `web/src/stores/collect.test.ts`

**Acceptance criteria:**
- [ ] The 註解 field is optional. Collecting with it empty behaves exactly as today.
- [ ] A typed note is sent with the card and is on the new card.
- [ ] A line already collected: the existing card is unchanged. The notice shows its note under the translation when it has one. When a note was typed, the notice says 註解沒有存進去, and the typed note stays in the field.
- [ ] After a successful collect the note field clears along with the rest of the panel, as the other fields do today.
- [ ] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** Collect a new line with a note: it shows on the card page. Collect the same line again with a different note: the notice shows the first note, says the new one was not saved, and the new one is still in the field.
