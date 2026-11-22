Status: implemented — awaiting PR and deploy (2026-11-22)

# 01 — The forecast on 字卡庫 and on the practice overview

**What to build:** the tiles of the spec on both pages, from the deck the page already holds. No backend change.

**Rules:**

- Days are **calendar days in the reader's time zone**, from the moment the deck was fetched (`loadedAt`), as the rest of practice counts days: 23:00 tonight to 09:00 tomorrow is 1 天.
- 今天 holds everything due on or before today's date: overdue cards, cards due later today, and learning cards due in minutes.
- New cards have no due date and are in no tile; the line under the tiles says how many there are.
- The tiles count the whole deck; neither the search nor the narrowing changes them.
- With no card out of `new`, neither page shows the tiles.

**Files (boundary):**
- `web/src/practice/forecast.ts` (new): the six tiles, `daysUntil`, `dueBucketOf`, `dueForecast`, `hasDueDates`, `dueLaterToday`, `isDueBucketKey`
- `web/src/practice/forecast.test.ts` (new)
- `web/src/components/DueForecast.vue` (new): the panel; tiles are buttons (`select`, `aria-pressed`) or, given `to`, links
- `web/src/views/DeckView.vue`: the panel under the title; the pressed tile in `?due=`; the narrowing bar; 這一格沒有卡片。
- `web/src/views/PracticeView.vue`: the panel under 開始複習, and in place of 明天到期 once the day is done
- `web/src/practice/overview.ts`, `overview.test.ts`: `dueTomorrow` removed, nothing else used it
- `DESIGN.md` 7.20 and `docs/design/` (via the design-system agent)

**Acceptance criteria:**
- [x] 字卡庫 shows 接下來要複習 with 今天 · 1 天 · 3 天 · 7 天 · 21 天 · 更久, each with its range (含已到期, 明天, 2–3 天後, 4–7 天後, 8–21 天後, 22 天以上); the counts plus the new cards add up to 共 N 張.
- [x] Pressing a tile lists only its cards, soonest first, with 只看：… and 看全部; the address carries `?due=`; pressing it again or 看全部 shows every card.
- [x] A tile with no cards narrows to 這一格沒有卡片。
- [x] The practice overview shows 之後幾天要複習 with 1 天 to 更久, under 開始複習 while cards are waiting, and in place of 明天到期 once the day is done.
- [x] A tile on the overview opens 字卡庫 narrowed to it.
- [x] Phone width: three tiles a row. Desktop: one row.
- [x] `npm run typecheck`, `npm run build`, `npm test` pass.

**Owner check after deploy:** on the phone and the Mac. 字卡庫: the six numbers plus 另有新卡 N 張 add up to 共 N 張; press 3 天 and every card listed says 2 or 3 天後; 看全部 brings the rest back. 練習: the five tiles are there whether or not cards are waiting; press 21 天 and 字卡庫 opens with 21 天 picked. Tomorrow morning, before practising, 練習's 1 天 tile from tonight should match what 今天有 N 張要複習 says (less any new cards).

## Comments

2026-11-22: implemented. `npm run typecheck`, `npm run build` and `npm test` pass: 526 tests in 28 files, 16 new in `src/practice/forecast.test.ts`, 5 removed with `dueTomorrow`. Checked in Chromium against the dev server on the real deck (read only; nothing was pressed that writes): 333 cards = 今天 0 + 1 天 60 + 3 天 32 + 7 天 28 + 21 天 73 + 更久 0 + 新卡 140. 3 天 narrowed to 32 cards, all 2 天後 or 3 天後, address `/deck?due=d3`; 今天 narrowed to 這一格沒有卡片。 The overview was in its finished-day state: 明天到期 gone, the five tiles above 所有字卡; 21 天 opened `/deck?due=d21` with that tile pressed and 73 cards. 390 px: three a row; 1280 px: one row of six. The waiting state was not seen on real data, as the day was already done; it was seen in the preview, and it renders the same component from the same counts.

Decisions made while implementing:
- The pressed tile lives in the address so the overview can link to it; set with `router.replace`, so pressing tiles leaves nothing for Back to step through.
- Narrowed, the list is sorted by due date, soonest first; unnarrowed it keeps the deck's order (newest first).
- The tile grid switches to one row by the panel's width (container query), not the window's, because 字卡庫 and the overview are not equally wide.
- 今天's number is drawn in the red of 已到期 when it is not zero; any zero is faint.
- `dueTomorrow` and its tests are removed; the 1 天 tile replaces the only place it was used. The `calendar` icon stays in `AppIcon` although nothing draws it now.

2026-11-22: the design docs are updated by the design-system agent: DESIGN.md 7.20 (new) and the sections it touches, `docs/design/page-design-spec.md` 2.4–2.6, `STATUS.md`, `contrast-report.md` §9 (both themes pass; lowest text contrast 5.32). It found three departures from DESIGN.md's general rules, settled by the main session before shipping:
- 看全部 was 36 high with no padding to 44: now padded with `before:-inset-1`, as 7.1 asks. No visible change.
- The tiles' bottom padding was 9px, off the spacing scale: now 8 (`pb-2`).
- 「只看：3 天（2–3 天後）・32 張」 uses a 中點, which §4 avoids: kept, as the owner saw and approved that line in the preview; recorded as a §12 exception.
