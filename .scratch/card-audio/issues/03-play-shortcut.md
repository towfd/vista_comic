Status: deployed — awaiting the owner's Mac check (2026-11-19)
Blocked by: 02

# 03 — ⌘3 plays the recording

**What to build:** On a Mac keyboard, ⌘3 does what pressing a play button does, so the owner can listen without reaching for the mouse. One button per screen answers the key: the recording of the card the question is about. Asked for by the owner on 2026-11-19, who picked the key.

**Decisions:**

| Question | Decided | By |
|---|---|---|
| The key | ⌘3 (Meta+3, no other modifier). Matched by `code === 'Digit3'`, so it is the key on the number row whatever the layout types. | Owner |
| Can a page take ⌘3 from the browser? | Yes in Chrome on the owner's Mac: a throwaway test page that called `preventDefault()` on ⌘3 played card 1's recording twice (nginx log, 2026-11-19 06:37:46 and 06:37:56, no page load in between), and the owner did not report a jump to tab 3. | Tested with the owner |
| Which button on a 填空題 (two buttons) | 整句, the card the question is about. One rule everywhere: ⌘3 plays the asked card. | Owner |
| Which button on a 整句題 | The one beside 卡片 (the only one). | Follows the rule |
| Card page | The one beside the source text. | Follows the rule |
| While a question is being asked | Nothing plays, as there is no button then (02). | Main session, following 02 |
| Does the practice page claim ⌘3 while nothing can play? | Yes: from the moment it is on screen, so a slip of the hand mid-question does not jump to tab 3. | Main session |
| Other pages (library, reader, deck list) | Leave ⌘3 to the browser. | Main session |
| ⌘3 while playing | Stops, as a second press does. Held key: one press. | Main session |
| A visible hint | None. One user, who chose the key; a phone has no ⌘. `aria-keyshortcuts="Meta+3"` on the button that answers it. | Main session |

**Files (boundary):**
- `web/src/audio/shortcut.ts` (new): whether a keydown is ⌘3; which press the key triggers (a button offers its press, takes it back when it leaves); a composable a page calls to claim the key while it is on screen
- `web/src/audio/shortcut.test.ts` (new)
- `web/src/components/CardAudioButton.vue`: a `shortcut` prop; offers its press while true and on screen; `aria-keyshortcuts`
- `web/src/views/PracticeSessionView.vue`: claims the key; `shortcut` on the 卡片 button when there is no cloze, on the 整句 button when there is
- `web/src/views/DeckCardView.vue`: claims the key; `shortcut` on its button
- `DESIGN.md` 7.19 and `docs/design/` (via the design-system agent): ⌘3 in 發音鈕's behaviour; the open question about a failed load is now decided (see Comments)

**Acceptance criteria:**
- [x] After an answer, ⌘3 plays the asked card: beside 卡片 on a 整句題, beside 整句 on a 填空題. The button shows the same states as a press.
- [x] ⌘3 again while it loads or plays stops it; holding the key does not toggle it over and over.
- [x] While a question is asked, ⌘3 plays nothing and stays on the page.
- [x] Card page: ⌘3 plays the card's recording.
- [x] Other pages: ⌘3 is left to the browser.
- [x] ⌘⇧3, ⌥⌘3 and Ctrl+3 do nothing on these pages.
- [x] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** On the Mac, in the browser used for vista_comic: answer a 整句題 and press ⌘3 (it speaks; ⌘3 again stops it). Answer a 填空題 and press ⌘3: the whole sentence plays, not the word. Open a card in 字卡庫 and press ⌘3. While a question is being asked, ⌘3 does nothing and the tab stays put.

## Comments

2026-11-19: the owner confirmed that every card has the female voice and that a failed load stays silent (02's open question: the button goes back to idle with no words).

2026-11-19: implemented. `npm run typecheck`, `npm run build` and `npm test` pass: 515 tests, 10 new in `src/audio/shortcut.test.ts`. Checked in Chromium against the dev server with every write blocked (the review POSTs failed with `net::ERR_FAILED`, and the api logged no write in those 20 minutes):
- Card page (card 19), with the cursor in the translation field: ⌘3 → 「停止播放」, ⌘3 again → 「播放發音」. ⌘⇧3, ⌥⌘3 and Ctrl+3 were not prevented and played nothing.
- Practice, 填空題: while asking, no button, ⌘3 prevented, nothing typed, the page stayed. After an answer only 「播放整句」 carries `aria-keyshortcuts="Meta+3"`; ⌘3 plays it (solid brand fill), and with 「播放這個字」 started by the mouse, ⌘3 takes over for 整句.
- Practice, 整句題 (question mix set to `sentence` in the browser, then removed): the button beside 卡片 carries the key; a keydown followed by a repeat (`repeat: [false, true]`) leaves it playing, so a held key presses once; ⌘3 again stops it.
- Library: ⌘3 not prevented.

Decisions made while implementing:
- Two halves in `src/audio/shortcut.ts`: a page claims the key (`useAudioShortcut`, a window keydown listener while mounted) and one button offers its press (`shortcut` prop). The claim is the page's, so ⌘3 is held back even while no button shows.
- The last button to offer wins, and a button takes back only its own offer, so the next question's button mounting before the last one unmounts cannot leave the key dead.
- Matched by `code`, not `key`; the keypad 3 (`Numpad3`) does not count.
- The design docs: DESIGN.md 7.19 and §10 describe ⌘3; §12 and `docs/design/STATUS.md` record the failed-load decision (design-system agent).

2026-11-19: merged as #168 (`9ee6174`) and deployed on this machine, which is the deploy host (`agent-Aspire-TC-1750`; SSH to it failed host key verification, so the deploy ran locally). Only `web` rebuilt (the change touched `web/`, docs and `.scratch/`). `localhost:8080/` answers 200, the served bundle (`index-yKyh657i.js`) carries `Digit3` and `Meta+3`, and `/cards/19/audio` answers 200.
