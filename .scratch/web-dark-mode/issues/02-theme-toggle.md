Status: done

# 02 Theme toggle: library header button, remembered choice

Spec: ../spec.md

## What
- A small theme module (e.g. `web/src/theme.ts`, same storage style as `practice/questionMix.ts`: `try`/`catch` around `localStorage`): read the remembered choice (`vista-theme`, `light`／`dark`), apply a theme (set/remove `data-theme="dark"` on `<html>`, set `theme-color` to `#FFFFFF`／`#1E1F45`), remember a choice. While nothing is remembered, follow `matchMedia('(prefers-color-scheme: dark)')` `change` events live; once the user presses the toggle, stop listening. Storage refused (private mode): follow the phone; a press applies for this visit only.
- The key and values must match the pre-paint script in `web/index.html` (ticket 01).
- `AppIcon.vue`: add `moon` and `sun` (paths in `DESIGN.md` §7.18).
- `LibraryView.vue` header (`:60-73`): the toggle left of the refresh button, per §7.18 — `iconButton` look, always shown (loading, error, empty too), moon + 「換成暗色」 in light, sun + 「換成亮色」 in dark, no `aria-pressed`, focus stays on it, instant switch (no fade).
- The toggle must not jump sideways when the refresh button appears after loading: keep the refresh button's 44px slot reserved while it is hidden (e.g. render it `invisible` rather than not at all), so neither button moves. (Agent decision 2026-11-16; DESIGN §7.18 is unchanged by this.)

## Acceptance
- Unit tests for the theme module: initial theme from remembered／phone; pressing remembers and stops following the phone; following the phone live before any press; storage throwing on read and on write.
- `npm run typecheck && npm run build && npm test` pass.
- In the browser: press → whole app switches at once and `theme-color` changes; reload keeps the choice; with nothing remembered, flipping the emulated `prefers-color-scheme` flips the app; after a press it no longer does. The toggle does not move when the library finishes loading.

Blocked by: 01

## Comments

2026-11-16 (frontend-builder, checked by the main session): done on `feature/web-dark-mode-02-toggle`.

- New `web/src/theme.ts` (`createTheme` takes storage, the phone's media query, `<html>` and `theme-color` as parameters, so the tests run without a DOM; `useTheme()` is the site's one instance) and `theme.test.ts` (11 tests: remembered／phone start, live follow before a press, press remembers and stops following, storage throwing on read and write, unknown stored value, no `theme-color` meta).
- `main.ts` calls `useTheme()` before mounting, so the phone is followed from whichever page opens first (the reader included).
- `AppIcon.vue`: `moon`, `sun` (DESIGN §7.18; the sun's centre circle written as a path).
- `LibraryView.vue`: the toggle left of refresh; refresh is rendered `invisible` until the library loads, so the toggle stays put (x = 276 at 390 and 1138 at 1440 while loading, loaded and on error) and the hidden button is out of the tab order and the accessibility tree.
- A switch briefly holds every transition (`transition:none` for one restyle), because buttons and switches ease colour over 120ms and would otherwise fade a beat behind the page; press transitions are intact afterwards. Browser-verified, not unit-tested.
- `npm run typecheck`, `npm run build` pass; `npm test` 25 files／492 tests pass (re-run by the main session).
- Browser, 390 and 1440: Enter／Space／click switch the whole page at once, `theme-color` and `localStorage` follow, focus stays on the button with its name and icon swapped; reload keeps the choice; with nothing stored, flipping emulated `prefers-color-scheme` flips the app live, and after a press it no longer does. Screenshots `docs/design/screenshots/dark/impl-02/` (not in git).
