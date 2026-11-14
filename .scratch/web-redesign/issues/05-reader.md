Status: done

# 05 閱讀器外觀：頂端列、泡泡三層框、收卡與深入查詢面板、本話完（§2.3、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
ReaderView.vue, ReaderPage.vue, CollectPanel.vue, AnalysisPanel.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01, 02

## Comments

- 2026-11-14 (frontend-implementer): Restyled the reader top bar, floating 標示／＋收卡, bubble rings, popover, page placeholder and load failure, 本話完, and the collect and analysis panels with DESIGN.md tokens. No logic in `reader/*.ts`, stores, api or router changed; the folder `title` still keys the overlay and the name table, the bar shows `displayTitle ?? title`. Decisions: the analysis panel is `z-39` (collect `z-40`) so 收卡 opened from a word still covers it; 收合 moved to the collect panel's header (page-design-spec 3.3); 「到字卡庫修改 ↗」 uses the external icon instead of the arrow character (DESIGN 7.2); the 重新查詢 confirmation is a warning message box. typecheck, build and 429 tests pass; visual QA at 390／1440 and a real-iPhone check still pending.
