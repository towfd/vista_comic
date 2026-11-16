Status: ready-for-agent (after the owner confirms the plan)

# Web dark mode: "星空藍" beside the pink-sticker light theme

## Problem Statement

Raised by the repo owner, 2026-11-16 (relayed by the managing session agent-2b): 「我們現在的頁面是亮色系的，我想要做一個暗色系的。有時候我會想用暗的，有時候想用亮的。我記得很多網站都可以自己切換。」

The web client is light only (`DESIGN.md` said so on 2026-11-14, `web/src/style.css:148`, `web/index.html:9`). The owner now wants to switch between light and dark themselves.

## Solution

Add a second colour set, **B 星空藍** (indigo night with the same pink and yellow), applied when `<html data-theme="dark">`; light stays the default and unchanged. One round icon button in the library header switches. Layout, type, radii, spacing and components do not change.

Design sources, in order of precedence:

1. `DESIGN.md` — §3 (dark values for every token), §7 (dark notes per component, §7.18 the theme toggle), §15.1 (`style.css` as it should be), §15.2 (`index.html` pre-paint script), §15.5 (the class replacements, with file:line).
2. `docs/design/contrast-report.md` — every dark pair checked.
3. `docs/design/previews/dark/index.html` (pick 「暗色 B 星空藍」) — the visual reference the owner chose from.
4. `docs/design/dark-mode.md` — the decision log for this feature.

## Decisions

Made with the owner on 2026-11-16 (log in `docs/design/dark-mode.md`; folded into `STATUS.md` when the docs branch merges).

| Question | Decision |
|---|---|
| Light only? | Overturned: light and dark, chosen by the user. Names in the UI and docs: 亮色／暗色. |
| Dark palette | B 星空藍 (page `#1E1F45`, band `#2C2560`, pink `#FF80B5` as both pink text and button fill with dark text `#24102A` on it). Covers keep their colours; sticker borders stay white; yellow and the text on it unchanged; manga pages never dim. |
| Default | First open follows the phone/computer (`prefers-color-scheme`), live, until the user presses the toggle. After that the choice is remembered in this browser (`localStorage`) and the phone is ignored. Only light and dark; no third "follow phone" option. Each device remembers on its own. |
| Toggle | Library header only, left of the refresh button. Moon in light (「換成暗色」), sun in dark (「換成亮色」). Not in the reader, deck or practice. |
| Status bar | `apple-mobile-web-app-status-bar-style` stays `default` (changing it needs the home-screen app re-added). `theme-color` follows the app's theme via script. Whether iOS honours it in the home-screen app is checked on the device. |

## Out of scope

A "follow phone" setting, per-page toggles, dimming manga pages, changing the manifest colours, iOS app.

## Tickets

- `issues/01-dark-foundation.md` — tokens, pre-paint, class replacements; dark follows the phone.
- `issues/02-theme-toggle.md` — the button and remembering the choice.
- `issues/03-dark-qa.md` — visual QA in both themes and the device checklist.
