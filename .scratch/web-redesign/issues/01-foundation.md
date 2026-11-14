Status: done

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

## Comments

2026-11-14 (frontend-implementer): done on `feature/web-redesign-foundation`.

- `style.css`: DESIGN §15.1 `@theme` + base (light only, `font-synthesis-weight: none`, focus ring, reduced motion); safe-area padding, the status-bar strip (now `--color-paper`), overscroll/tap/callout/user-select rules and `--breakpoint-dock` kept. Built-in palette not cleared yet (`--color-*: initial` stays commented until every page is converted).
- `index.html` / manifest: `#FFFFFF`, status bar `default`, `color-scheme` meta, Nunito + Huninn.
- `NavBar.vue` removed; `TabBar.vue` (書庫／字卡／練習, `aria-current`, 52px cells, Home-bar clearance, sun badge with bump/leave motion) shown where route meta `tabBar: true` (library, deck, practice overview). Icons in `AppIcon.vue`.
- Deck load-on-library and refresh-on-visible moved to `App.vue` so the badge stays fresh while the bar is unmounted. App.vue also registers the no-op `touchstart` listener that makes `active:` styles work on iOS (DESIGN §7 says main.ts; main.ts was outside the boundary).
- Tab pages get `pb-19` (52 + 24) from App.vue; the body's safe-area padding already clears the Home bar, so DESIGN §5's `calc(4.75rem + env(...))` would double-count it.
- `ErrorState.vue`: sticker per kind, primary md 重試; `#actions` slot exposes `buttonClass` (secondary, or primary when there is no retry).

Left for later tickets: views still use the old dark classes; shared loading and empty-state components do not exist yet (outside this boundary); DESIGN §7.15 sticker needs `outline-offset-5` (added here) for the white gap the preview shows.
