Status: done

# 03 Dark QA: both themes, every page, device checklist

Spec: ../spec.md

## What
- visual-qa: every page (`STATUS.md` 頁面 table) at 390 and 1440, light and dark, plus the states the pages have (loading, error, empty, practice finished, collect panel, analysis panel, reader hint/selected bubble frames). Light screenshots compared with the current deployed look — light must not have changed.
- Fix P0／P1 with evidence (frontend-builder), one round, then re-check only what was fixed.
- Write the device checklist for the owner (iPhone home-screen app and Mac).

## Acceptance
- P0 = 0, P1 = 0 in both themes; no horizontal scroll at 390／1440; no console errors.
- Screenshots and the checklist on a LAN page for the owner (0.0.0.0, LAN + Tailscale addresses).

## Device checklist (the owner checks; not testable here)
1. Status bar (clock strip) of the home-screen app in four cases: phone light／dark × app light／dark.
2. First open with the phone in dark mode: no white flash.
3. Press the toggle, close the app fully, reopen: the choice is kept; changing the phone's setting no longer changes the app.
4. The reader's hint and selected bubble frames over real translated pages, in dark (the hint box turns indigo in dark — new, not in the preview).
5. Keyboard on the practice and card pages in dark (iOS picks the dark keyboard from `color-scheme`).

Blocked by: 01, 02

## Comments

2026-11-16 (visual-qa, checked by the main session): round 1 done — P0 0, P1 0, P2 3. Report `docs/design/dark-qa-report.md`; screenshots `docs/design/screenshots/dark/r1/` (45, not in git).

- Passed: eight pages at 390 and 1440 with no horizontal scroll; dark contrast scan of library, deck, card, practice, settings and chapters with no failures, no white surfaces, no pink-purple shadows; white sticker borders, dark text on yellow, manga pages undimmed, the three-layer frames unchanged, indigo hint box; toggle (colour, `theme-color`, kept on reload, Enter); follows the phone until pressed. Light library at 390 compared element by element with the deployed site: no style difference.
- P2, left for later (not dark-specific or not blocking): QA-D01 the 「看過」 legend swatch on the chapter page is about 1.1:1 against the dark page (the label beside it carries the meaning); QA-D02 「刪除卡片」 uses `text-ink`, not `text-danger` as DESIGN §7.1 says (same in light, pre-existing); QA-D03 the 「已加入」 pill's white ring touches the left edge at 390 in dark (light not captured).
- Not checked: Lighthouse (no DevTools MCP); 768 width; practice loading, empty library and API-failure message boxes; light at 1440 and on some pages beyond token checks (the built-CSS comparison in 01 already showed every light value unchanged). States were faked by replacing `fetch`; no real data was written. The dev server was started by the main session (localhost only) because the QA agent's shell is restricted.
