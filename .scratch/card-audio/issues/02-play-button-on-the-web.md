Status: done (2026-11-19)
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
- [x] No play button while a question is being asked.
- [x] After an answer, the buttons above appear only for cards with `hasAudio`.
- [x] A press plays; a second press while playing stops; starting another stops the first.
- [x] Card page: button when `hasAudio`, the sentence when not.
- [x] Light and dark both checked at a compact and a larger phone width.
- [x] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** On a phone, answer a 整句題 and press the button beside 卡片: it speaks. Answer a 填空題: the word and the sentence each play. Open a card in 字卡庫 and press the button beside the source text.

## Comments

2026-11-18: implemented. `npm run typecheck`, `npm run build` and `npm test` pass: 505 tests, 13 new (11 in `src/audio/player.test.ts`, 2 in `client.test.ts`). Checked in a browser against the dev server with every write blocked, `hasAudio` set in the browser and a test tone served for `/cards/{id}/audio` (no card had audio yet): no button while asking (整句題 and 填空題); after an answer, 「播放發音」 on a 整句題, 「播放這個字」 (card 185, the cloze's word card) and 「播放整句」 (card 186) on a 填空題; a press plays (solid brand fill, 「停止播放」), a second press stops, pressing the other button takes over, the end of the recording returns it to idle, and a 404 returns it to idle. Card page: the button beside the source text when `hasAudio`, the sentence when not. 375 and 430 wide, light and dark: no horizontal scroll, the button 16px from the edge, never over the text.

Decisions made while implementing:
- One shared player (`src/audio/player.ts`) with one audio element, created on the first press. Each button is its own owner (a symbol), not a card id, so two buttons for one card would still be told apart.
- `play()` is called inside the press itself, because iOS Safari only plays what a touch started.
- A button that leaves the screen (下一題, leaving the page) or moves to another card stops its own recording.
- A failed load says nothing on screen; the button goes back to idle and can be pressed again.
- Labels: 「播放發音」 beside 卡片 and on the card page, 「播放這個字」 and 「播放整句」 on a 填空題, 「停止播放」 while loading or playing.

Design docs: the design-system agent added DESIGN.md 7.19 (named 發音鈕 there, because 7.1 already has a 播放鈕 for the library's continue-reading card), 發音 to the §13 word list, two §12 exceptions (the loading spin that can be pressed, and a failed load with no words), and the matching rows in `docs/design/` (page-design-spec 2.7, 3.5, 3.7 and §8; contrast-report §8; STATUS). Every combination passes in both themes with existing tokens. The writing manager proofread it (`docs/writing-log.md`, 2026-11-18 第 5 次). Open for the owner: whether a failed load should say something (STATUS, 待使用者決定); that behaviour was decided here while implementing, not by the owner.

2026-11-18: merged as #163 (`a53645e`) and deployed: only `web` rebuilt (the change touched `web/`, docs and `.scratch/`). The served bundle carries 「播放這個字」「停止播放」 and the no-audio sentence. No card has audio until the Text-To-Speech writer runs, so the owner's phone check waits for that.

2026-11-19: the `text-to-speech` session wrote a recording for every card: 324 / 324 answer `hasAudio: true` through `localhost:8080/cards`, and `/cards/{218,225,228,235}/audio` answer 200 `audio/mpeg`. Card 19's text was corrected (SẮP XẾT LẠI → SẮP XẾP LẠI) through `PUT /cards/19/source-text`, and its recording matches the corrected text. The owner checked on a phone: after an answer the recording plays, the button on the card page plays, and cards with odd and even ids have different voices. Not seen on the production site: the button hidden for a card without a recording, because every card has one now; it was checked in the browser on 2026-11-18.
