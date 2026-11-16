Status: ready-for-agent

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
