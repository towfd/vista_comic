Status: done

# 03 書庫：繼續看大卡、兩欄貼紙封面、狀態（page-design-spec §2.1、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
LibraryView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01, 02

## Comments

2026-11-14 (frontend-implementer, branch `feature/web-redesign-03-library`):
- 繼續看 numbers: page-design-spec §7 item 1, front-end option. `web/src/library/continueReading.ts` picks the latest `lastReadAt`; the view then calls `useComicsStore().load(id)` for that one comic (revalidated per visit) and derives 「看到第 N 話」 from the chapter's `number` and 「pos / total」 + bar from its place in `chapters`. Until the detail arrives (or if it fails / lacks the chapter) the card shows tag, title and play button only, play `aria-label` 「繼續閱讀」. The detail's `continueChapterId` wins over the list's (fresher).
- Shelf cell of the comic being read shows 「看到第 N / M 話」 (N = chapter number, M = chapter count from the detail) in `text-brand`; all others 「N 話」.
- DESIGN over page spec: progress track `bg-paper inset-ring-line` + `bg-brand-vivid` fill (7.12, white card) instead of `--blush-2`/`--pink`; 話數 under shelf titles `text-meta` (type scale) rather than 13; refresh spin `animate-spin` (1s, DESIGN 7.16) rather than 900ms.
- New string: progress bar `aria-label` 「閱讀進度」 (not in §8). The sticker's link duplicates the title link, so it is `aria-hidden` / `tabindex=-1`.
- Known limit (outside this ticket's files): `useLibraryStore` loads once per session, so after reading a *different* comic the card keeps pointing at the previous one until 重新整理. For the same comic, the detail revalidation keeps the chapter current.

