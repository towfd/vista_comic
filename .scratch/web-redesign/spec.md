Status: ready-for-agent

# Web redesign: light "pink sticker" look, bottom tabs, display titles

## Problem Statement

Raised by the repo owner, 2026-11-14. On the phone (home-screen PWA) the web client still reads as a dark web page: folder-name titles like `lam_nong_dan_trong_toa_thap_thu_thach`, a text-only nav bar at the top, one grey and one blue for everything, a chapter list that looks like a spreadsheet, and empty practice screens.

## Solution

Restyle every page of `web/` to the chosen direction, **round 2 direction C "粉紅貼紙"** (`docs/design/previews/round2/direction-c.html`), light only, with a bottom tab bar, and show proper Vietnamese titles from an optional `title.txt` per comic folder.

The design sources, in order of precedence:

1. `DESIGN.md` (repo root) — tokens, components, states, contrast rules, and §15 "實作對照" (the `@theme` block and class mapping for Tailwind v4).
2. `docs/design/page-design-spec.md` — page-by-page layout, every state (loading, error, empty), motion, wide screens, new copy (§8).
3. `docs/design/previews/round2/direction-c.html` — the visual reference.

Where (1) and (2) disagree, `DESIGN.md` wins (it already reconciled the spec, see its §15.6).

## Decisions

Made with the owner on 2026-11-14 (full log in `docs/design/STATUS.md`).

| Question | Decision |
|---|---|
| Theme | Light only. `color-scheme: light`; no `prefers-color-scheme: dark` styles. Status bar `default`, `theme-color` and manifest colors `#FFFFFF`. |
| Direction | Round 2 C: white + blush, brand pink `#FF4F8B` for shapes only, `#C81A60` for buttons and pink text, yellow `#FFD23F` accents. Nunito + 粉圓 Huninn. |
| Navigation | Bottom tab bar 書庫／字卡／練習 on the library, deck and practice overview only. Sub-pages keep a back button. The practice tab badge keeps today's algorithm (`standing.remaining`). |
| Chapter list | Number grid, five per row; read dimmed, current in pink; scrolls to the current chapter on arrival from the library; no page counts. Decimal numbers (`54.1`) must fit. |
| Titles | Optional `title.txt` in each comic folder. Backend adds `displayTitle: string | null` to `GET /comics` and `GET /comics/{id}`. `title` (folder name) is unchanged: `comic-ocr-data` and the reader's name table are keyed by it. Drafts in `docs/design/titles.md`, approved. |
| "今天做完了" | No day-level answer statistics. Right／wrong／graduated move to the round-finished screen; the overview shows 明天到期 and the deck's stage distribution. |
| Reader | Header hide/reveal behaviour (`reader/headerReveal.ts`) unchanged; only its look changes. Bubble outline is the three-layer frame from `DESIGN.md`. |
| Rollout | One PR per ticket; deploy once, after all tickets, with the `title.txt` files placed on the host. |

## Wire contract

- `ComicSummary.displayTitle: string | null` and `ComicDetail.displayTitle: string | null`.
- Source: `<library>/<comic folder>/title.txt`, UTF-8, first non-blank line, trimmed. Missing, unreadable or blank → `null`.
- Web shows `displayTitle ?? title`. Anything keyed by the folder (OCR data, name table) keeps using `title`.

## Compatibility

iOS ignores unknown fields and keeps showing `title`. No database change.

## Out of scope

Dark mode, per-chapter thumbnails, day-level review statistics, iOS.
