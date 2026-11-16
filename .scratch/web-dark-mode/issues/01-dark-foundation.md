Status: ready-for-agent

# 01 Dark foundation: tokens, pre-paint theme, class replacements

Spec: ../spec.md

## What
- `web/src/style.css`: exactly as `DESIGN.md` §15.1 — `@custom-variant dark` on `data-theme`; in `@theme` drop `--color-white`, add `--color-on-fill`, `--color-on-sun`, `--color-sticker`, shadow values referencing `--shade-*`／`--color-line`／`--color-brand-edge` (`shadow-float`, `shadow-ring-*` stay literal); in `@layer base` the light `--shade-*` and the whole `:root[data-theme='dark']` block with `color-scheme: dark`. Keep `@theme` (not `@theme inline`). Light output must be identical to today.
- `web/index.html`: §15.2 — `color-scheme` meta `light dark`, the pre-paint script before the stylesheet (key `vista-theme`, values `light`／`dark`, falls back to `prefers-color-scheme`), `theme-color` set by it. Status-bar style stays `default`. Rewrite the "Light only" comment.
- Every replacement in `DESIGN.md` §15.5 「加暗色時要換的 class」 except the last row (the toggle is ticket 02): `text-white`→`text-on-fill`, `bg-white`→`bg-on-fill`, sticker `border-paper`→`border-sticker`, text on `bg-sun`→`text-on-sun`. Then the searches listed under 「換完要確認」 must come back as stated.
- No toggle yet: after this ticket the theme comes from the phone/computer setting at page load (or a hand-set `localStorage['vista-theme']`).

## Acceptance
- `npm run typecheck && npm run build && npm test` pass.
- Built CSS: in light, every colour and shadow value equals today's (diff the built CSS of `main` and this branch for the light values); with `data-theme="dark"` on `<html>` the checks in §15.1 「改完怎麼驗」 hold (page `#1E1F45`, pink button with dark text, edge `#C23A78`, white sticker borders, black shadows).
- With the browser emulating `prefers-color-scheme: dark`, a reload paints dark from the first frame (no white flash) and `theme-color` is `#1E1F45`.
- `grep` in `web/src`: no `text-white`／`bg-white`／`border-white`／`ring-white`／`border-paper`／`dark:`.

Blocked by: none

## Comments
