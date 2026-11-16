Status: ready-for-agent

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
