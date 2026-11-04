Status: done — owner confirmed on the deployed web (2026-11-04)
Blocked by: 01

# 02 — Show the note after answering

**What to build:** In a practice session, a card's note appears once the question is answered, in its own 註解 section at the bottom of the feedback.

**Files (boundary):**
- `web/src/views/PracticeSessionView.vue`: only this file

**Acceptance criteria:**
- [x] While the question is open, no note is shown.
- [x] After a right answer, a wrong one, or 算我對, a card with a note shows a section headed 註解 below the 算我對 / 下一題 buttons and above 這張卡片有問題？到字卡庫修改 ↗. The note's line breaks are kept.
- [x] A card with no note shows no section and no heading.
- [x] Applies to both cloze and whole-sentence questions.
- [x] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** Answer a card with a note right, then one wrong: the note is at the bottom both times, and not visible before answering. A card without a note looks as it does today. A long note wraps on a compact and a larger phone.

## Comments

2026-11-04: implemented. The section sits inside the feedback section, which exists only once a question is answered, so it cannot show while one is open. typecheck, build and 417 tests pass. The view has no unit tests: placement, the empty case and both question types are for the owner check.

2026-11-04: merged (#140, #141, #142), deployed with `api` + `web` rebuilt (migration `b6e2f0c4a913` applied on start), and confirmed by the owner on the deployed web.
