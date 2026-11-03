Status: implemented — awaiting deploy check by owner (2026-11-04)
Blocked by: 01

# 03 — Write a note when collecting

**What to build:** The web reader's collect panel has an optional 註解 field under the translation. It is sent with the card. When the line was already collected, the notice shows the existing card's note and says the typed note was not saved.

**Files (boundary):**
- `web/src/components/CollectPanel.vue`
- `web/src/stores/collect.ts`, `web/src/stores/collect.test.ts`

**Acceptance criteria:**
- [ ] The 註解 field is optional. Collecting with it empty behaves exactly as today.
- [x] A typed note is sent with the card and is on the new card.
- [x] A line already collected: the existing card is unchanged. The notice shows its note under the translation when it has one. When a note was typed, the notice says 註解沒有存進去, and the typed note stays in the field.
- [x] After a successful collect the note field clears along with the rest of the panel, as the other fields do today.
- [x] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** Collect a new line with a note: it shows on the card page. Collect the same line again with a different note: the notice shows the first note, says the new one was not saved, and the new one is still in the field.

## Comments

2026-11-04: implemented. The store is covered by 5 new and 2 updated tests in `collect.test.ts`: a note is sent trimmed with its line breaks, a blank one is not sent at all, the cap blocks adding, the field clears after a new card, and an already-collected line reports `noteDropped`, keeps the typed note and stops saying so once it is edited. The panel itself is not unit-tested. Typecheck, build and 422 tests pass.

One file outside the boundary: `web/src/api/client.ts`, for `CardDraft.note` (a type only).
