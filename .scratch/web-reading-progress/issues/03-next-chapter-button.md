# 03 — Next-chapter button at the end of a chapter

**What to build:** Below 「本話完」, a primary button 「下一話 · 第 N 話」 that opens the following chapter from its top. The existing 「回到章節列表」 link stays beneath it. Rules are in the spec's "Next-chapter button" section:

- **Next comes from the comic's chapter list**: the comics store's cached `GET /comics/{comicId}` if present, otherwise fetched in the background without blocking the pages. Next = the entry after the current chapter id.
- **Hidden** on the last chapter, when the current id is not in the list, and until the list has arrived.
- **Opens at the top**, ignoring the next chapter's `lastReadPage` (as iOS auto-advance), through ticket 02's top override. The flag rides in `history.state` and is **cleared once applied**, so a reload resumes from the saved position. The gate still protects the next chapter's saved position until the reader scrolls.
- **`router.replace`**, so browser back after 5 → 6 → 7 returns to the chapter list.
- **Pressing it flushes progress** (ticket 02's flush) — with 「本話完」 visible that is `pageCount`.

**Blocked by:** 02

**Status:** done 2026-10-06 — button, background list load, start-at-top flag in history state; merged in #104 and browser-verified by the developer.

- [x] Pure `nextChapter(chapters, currentId)` with unit tests: middle → following; last → none; unknown id → none
- [x] Button renders below 「本話完」 with the next chapter's number; hidden in the three cases above
- [x] Reader loads the comic detail in the background when the store lacks it; pages are never blocked on it
- [x] Next chapter opens at its top even with a saved position; reload mid-chapter resumes instead of restarting
- [x] `router.replace` navigation; progress flushed before leaving
- [x] `vue-tsc` clean, vitest green

## What was built

- `web/src/reader/nextChapter.ts` — pure, no DOM:
  - `nextChapter(chapters, currentId)` → the entry after `currentId`, or `null` on the last chapter, an unknown id, or a missing/empty list.
  - `START_AT_TOP_KEY` (`'vistaStartAtTop'`) and `takeStartAtTopFlag(state)` → `{ startAtTop, rest }`: the flag, plus the state without it (every vue-router key kept); `rest` is `null` when there is nothing to clear.
- `web/src/views/ReaderView.vue`:
  - `takeStartAtTop()` now reads the flag from `window.history.state` and, if present, clears it with `history.replaceState(rest, '')` (same URL). It is still called only from `position()`, i.e. after the *new* chapter's data has rendered — vue-router writes the replace's history entry before the props change, so the flag is there for the new chapter and the old one (already positioned) never sees it.
  - A `watch(props.comicId, immediate)` calls `comics.load(comicId)` (not awaited) when the store has neither data nor a load in flight. The pages do not depend on it.
  - `next = nextChapter(comics.entry(comicId).data?.chapters, chapterId)`; the button `v-if="next"` sits below 「本話完」, above 「回到章節列表」 (end block is now a centred flex column). Style matches the comic page's Continue button (`bg-sky-600`, white, medium).
  - `openNext()` → `flushProgress()` then `router.replace({ name: 'reader', params, state: { [START_AT_TOP_KEY]: true } })`. The param change then runs `openChapter` (its own flush is a no-op: same page).

## Verification done

- `npm run typecheck` (vue-tsc) clean; `npm run build` OK; `npm test` 72/72 across 6 files (8 new in `reader/nextChapter.test.ts`: middle / first → following, last → none, unknown id → none, missing/empty list → none; flag read with vue-router keys preserved, absent → nothing to clear, non-object state, non-`true` value cleared but not honoured). The count includes a concurrent agent's new `stores/comics.test.ts`.
- No network writes made for this ticket.
- Not exercised here: the browser behaviour (checklist below).

## Browser checklist for the developer

- [x] End of a chapter → button names the right chapter; pressing it opens that chapter at its top, even one read halfway on the phone
- [x] The finished chapter shows 已讀 afterwards
- [x] Last chapter → no button
- [x] Two hops, then browser back → chapter list
- [x] Open a reader URL directly (fresh tab) → the button still appears once the list arrives
- [x] After a hop, scroll a little, reload → resumes there, not at the top
