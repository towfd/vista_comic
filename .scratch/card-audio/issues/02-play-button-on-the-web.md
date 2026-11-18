Status: blocked
Blocked by: 01

# 02 — Play button on the web

**What to build:** A round play button that plays a card's recording on a press, in practice after an answer and on the card page. Decisions are in the spec's Comments; the screenshot preview the owner approved is the reference.

**Files (boundary):**
- `web/src/api/types.ts`: `hasAudio: boolean` on `LearningCard` (a response without it reads as `false`)
- `web/src/api/client.ts`: the audio URL for a card
- `web/src/components/AppIcon.vue`: `speaker` and `stop` icons
- `web/src/components/` a play button component: idle (speaker) → loading (spinning) → playing (solid brand fill, stop icon; a press stops) → idle when it ends; one recording at a time across the page; a failed load returns to idle with no crash
- `web/src/views/PracticeSessionView.vue`: buttons only in the feedback section — beside 卡片 on a 整句題; beside 空格裡的字 (the cloze answer card) and 整句 (this card) on a 填空題; none for a card whose `hasAudio` is false
- `web/src/views/DeckCardView.vue`: beside the source text; 「還沒有發音，下次產生發音時會補上。」 when `hasAudio` is false
- `DESIGN.md` (via the design-system agent): the play button component, its states, and 發音 in the §13 word list
- Web tests where the client or types change

**Acceptance criteria:**
- [ ] No play button while a question is being asked.
- [ ] After an answer, the buttons above appear only for cards with `hasAudio`.
- [ ] A press plays; a second press while playing stops; starting another stops the first.
- [ ] Card page: button when `hasAudio`, the sentence when not.
- [ ] Light and dark both checked at a compact and a larger phone width.
- [ ] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** On a phone, answer a 整句題 and press the button beside 卡片: it speaks. Answer a 填空題: the word and the sentence each play. Open a card in 字卡庫 and press the button beside the source text.

## Comments
