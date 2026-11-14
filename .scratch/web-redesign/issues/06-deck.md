Status: done

# 06 字卡庫與單張字卡（§2.4、§3）

Spec: ../spec.md. Follow DESIGN.md (wins) and docs/design/page-design-spec.md.

## Files
DeckView.vue, DeckCardView.vue（do not edit ErrorState.vue, NavBar/tab bar, App.vue or style.css — owned by 01）

## Acceptance
- Every state in page-design-spec for these screens (loading, error, empty, boundary) rendered with DESIGN.md tokens.
- Titles shown as `displayTitle ?? title` where a comic title appears.
- `npm run typecheck && npm run build && npm test` pass; 390 and 1440 have no horizontal scroll.

Blocked by: 01

## Comments

2026-11-14 (frontend-implementer): done on `feature/web-redesign-06-deck`, based on 02 (`b5c62aa`).

- Deck: 字卡庫 title + 「共 N 張」 count chip (hidden until loaded), blush pill search, `<details>` groups with count chip and a rotating chevron (native marker hidden), white ring cards with a state chip (coloured by `web/src/deck/cardState.ts`) and due text (已到期 in `text-st-relearn`), Vietnamese `lang="vi"` 2 lines (sentences 3 lines, `text-label`), Chinese 2 lines. Empty deck → EmptyState (`cards` icon, existing sentence split into title + hint) with primary 「到書庫」; no search result → search icon + existing sentence; empty group → existing line.
- Card page: round back button (`aria-label` 回到字卡庫), chip + due split, success/danger/warning message boxes, field saves secondary+disabled until changed then primary md, segmented kind switch (`aria-pressed` kept), dashed-rule destructive area stacked on phones and in a row from `sm`, secondary/secondary-danger → warning/danger solid on the confirming press, text 「取消」. Every handler, validation and string unchanged.
- No comic title appears on these screens, so the `displayTitle` criterion has nothing to apply to here.
- Deviations: width is `max-w-page` (640, DESIGN §6) rather than page-design-spec's 680; textareas keep `resize-y` (page-design-spec 3.5 says 可拉高; there is no auto-grow to keep); saving buttons do not switch to 「儲存中…」 (the page has no per-field busy state today, and adding one is new behaviour).
- Verification: `npm run typecheck && npm run build && npm test` pass (21 files, 438 tests, incl. new `deck/cardState.test.ts`). Visual QA at 390 / 1440 left to the main session.

