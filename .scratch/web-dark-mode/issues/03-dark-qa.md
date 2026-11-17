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

2026-11-17 (main session): the three P2s, closed on branch `fix/web-dark-mode-p2`.

- QA-D02 fixed. Cause: `secondaryBase` carried `text-ink`, and `.text-ink` comes after `.text-danger` in the built CSS, so the appended `text-danger` never won. `buttons.ts` now leaves the colour out of the base and each variant adds its own. Measured: light `#C8322A`, dark `#FF948A`, icon follows; the other secondary buttons have the same classes as before.
- QA-D03 fixed, and it was worse than reported: with 標示 shown, the row was 34px off the left edge and ＋收卡 was cut on the right. Not QA's `pl-2` (the row is right-anchored and grows leftwards, so left padding does not stop it): the row in `CollectPanel.vue` is capped at the screen width less 12px each side, and the pill (`min-w-0`) shrinks and ends the word in …. Measured at 390: row 12–378px, both themes.
- QA-D01 fixed: the owner compared three options at 390 dark (as is／a thin ring／`blush-strong` fill), first chose to leave it, then chose the fill. The 看過 legend swatch in `ComicView.vue` is `bg-mist-swatch`, a new token (light `#F5EEF1` = mist, so light is unchanged; dark `#3D3080` = blush-strong), not `dark:` (DESIGN line 41, §11). The chapter tiles keep `bg-mist`. Contrast light 1.14, dark 1.45 (was 1.13): recorded in DESIGN §3 and §10 as an exception, since the label beside it carries the state. Not the ring the plan first said: a ring would make 看過 look like 還沒看's outline (DESIGN §7.7: solid vs outline). DESIGN §3, §7.7, §10, §14, §15.1 and `docs/design/` (tokens, contrast report, STATUS) updated by design-system-architect.
- Verified: `npm run build`; `npm test` 492 passed. Screenshots by the main session with every non-GET request blocked (no reading progress written); this chapter has no OCR data locally, so 標示 was a same-width stand-in.
- Device check for the owner after deploy: 刪除卡片 is red on a card page (light and dark); collect a long line in the reader on the iPhone and the 已加入 pill stays on screen.

2026-11-17 (main session): deployed. PR #159 merged and main `bab4717` deployed (rebuilt `api` and `web`; `api` because #160 changed the backend). The live CSS has `mist-swatch` (light `#f5eef1`, dark `#3d3080`); site 200, `api` healthy. The owner's device check above still stands.
