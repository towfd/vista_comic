Status: ready-for-agent

# 04 章節頁：貼紙頁首、數字格、捲動後小頂列（§2.2）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
ComicView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01, 02

