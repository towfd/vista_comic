Status: done

# 04 章節頁：貼紙頁首、數字格、捲動後小頂列（§2.2）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
ComicView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01, 02

## Comments

2026-11-14 (frontend-implementer): Done on `feature/web-redesign-04-chapters`. `ComicView.vue` rebuilt as blush header (round back, +3° sticker cover with eager load, fade-in and book-icon fallback, `displayTitle ?? title` with `lang="vi"`, 「N 話」, primary lg 繼續閱讀＋第 N 話), legend 看過／正在看／還沒看, and a five-column number grid (`sm:` auto-fill 4.5rem) with read／current／unread looks and aria-labels incl. 看到一半. Pure rules in `web/src/chapters/grid.ts` (+ tests); `chapters/arrival.ts` records `popstate` so a back/forward arrival keeps the router-restored scroll while a push jumps instantly (rAF after the router's own scroll) so the current cell sits 35% down. Compact sticky bar (`top-[env(safe-area-inset-top)]`, zero-height wrapper) slides in when an IntersectionObserver sees the header gone above the screen. Loading = header skeleton + LoadingState; not found = ErrorState + 回到書庫; no chapters = header + EmptyState + 回到書庫 (primary, DESIGN 7.15). Decisions: the reader's in-app back is a push, so it also jumps to the current chapter; the bar watches the whole header rather than only the button (26px later, works without a Continue button); per-chapter titles and page counts are no longer shown (spec 2.2); 5+ character labels use `text-body` (DESIGN 15.6 maps 15 → 16). Visual QA at 390 and 1440 still to run.
