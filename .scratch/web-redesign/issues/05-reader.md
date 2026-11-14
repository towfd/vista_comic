Status: ready-for-agent

# 05 閱讀器外觀：頂端列、泡泡三層框、收卡與深入查詢面板、本話完（§2.3、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
ReaderView.vue, ReaderPage.vue, CollectPanel.vue, AnalysisPanel.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01, 02

