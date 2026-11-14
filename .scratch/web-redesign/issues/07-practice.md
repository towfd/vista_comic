Status: done

# 07 練習總覽、今天做完了、設定、練習中與回饋、這一輪做完了（§2.5–2.7、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
PracticeView.vue, PracticeSettingsView.vue, PracticeSessionView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01

## Comments

- 2026-11-14 (frontend-implementer): Restyled the overview (今天 + 設定 pill, blush card with proportional bubbles, 開始複習; empty deck → EmptyState + 到書庫), 今天做完了 (sun sticker, 明天到期 row in a blush card, 所有字卡 distribution bar + legend in a white card), settings (row switches, 7.8 fields and errors, saving/saved/failed) and the session (✕ 結束, progress bar, 還剩 N 張, question card with state chip, blank and 中文提示, answer field, 送出/下一題 in normal flow, every feedback state, note, edit link, checking via LoadingState, 這一輪做完了 with 答對/答錯/畢業). New pure helpers in `web/src/practice/overview.ts` (+ tests): `dueTomorrow` (non-new cards whose `dueAt` falls on the local date after `loadedAt`), `stageDistribution`, `bubbleLayout`/`bubblesHeight`, and the aria-label strings. No day-level answer statistics, per the spec decision.
  - Deviations: the 明天到期 row sits in its own blush card above the white distribution card (DESIGN 7.5/7.6 put the single row in a blush card; page-design-spec 2.6 had it inside the white one). Bubble container grows past 178px when near-equal counts push the lowest bubble down (`bubblesHeight`). Settings' 儲存 no longer uses `disabled` while saving (DESIGN 7.1 keeps the colour); a second press is refused in `save()` instead. Progress bar's `aria-label` 「這一輪的進度」 is new text.
  - Not verified here: visuals at 390/1440 (main session's visual QA). Known boundary to check: three near-equal counts put the third bubble's right edge at centre+184px, past the blush card at 390 (still inside the viewport).
