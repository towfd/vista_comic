Status: ready-for-agent

# 07 練習總覽、今天做完了、設定、練習中與回饋、這一輪做完了（§2.5–2.7、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
PracticeView.vue, PracticeSettingsView.vue, PracticeSessionView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01

