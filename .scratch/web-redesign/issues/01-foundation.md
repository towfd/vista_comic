Status: ready-for-agent

# 01 Foundation: light tokens, fonts, status bar, bottom tab bar

Spec: ../spec.md

## What
- Put the `@theme` and base blocks from `DESIGN.md` §15.1 into `web/src/style.css`, keeping the safe-area, `dock` breakpoint and PWA rules. Light only.
- Google Fonts (Nunito + Huninn) in `web/index.html`; status bar `default`; `theme-color` `#FFFFFF`; manifest colors `#FFFFFF`.
- Replace the top `NavBar` with the bottom tab bar (書庫／字卡／練習, icons, badge) shown on the library, deck and practice overview only (page-design-spec §1). Move the deck load/refresh-on-visible logic out of the bar so the badge stays fresh.
- Restyle the shared `web/src/components/ErrorState.vue` (loading/error/empty patterns from page-design-spec §3) since every page uses it.
- Unconverted pages may look wrong until their own tickets land; that is expected (single deploy at the end).

## Acceptance
- `npm run typecheck && npm run build && npm test` pass.
- Tab bar at 390 and 1440 matches DESIGN.md; no horizontal scroll; Home-bar clearance.

Blocked by: none

