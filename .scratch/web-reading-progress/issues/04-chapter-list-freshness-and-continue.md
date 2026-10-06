# 04 — Chapter list stays fresh and offers Continue

**What to build:** The chapter list reflects what was just read, and gets a 「繼續閱讀 · 第 N 話」 button. Rules are in the spec's "Chapter list freshness" and "Continue button" sections:

- **Stale-while-revalidate**: every visit renders the cached comic detail at once and refetches `GET /comics/{comicId}` in the background; no flash, no 「載入中」 when a cached copy exists.
- **The refetch waits for any in-flight progress save** (ticket 02's observable save), so badges include the chapter just left.
- **Continue**: under the title, above the chapters, primary style; N = `number` of the chapter whose id is `continueChapterId`; opens the reader normally (resumes at `lastReadPage`). Always shown — with no progress it points at chapter 1.
- **Hidden when `continueChapterId` is absent or not in the list**, so this can merge before ticket 01 is deployed.
- The library screen is unchanged.

**Blocked by:** 01, 02

**Status:** done 2026-10-06 — stale-while-revalidate comics store and the Continue button are in; merged in #104 and browser-verified by the developer.

- [x] `types.ts`: `ComicDetail.continueChapterId?: string`; client decoding unit-tested with and without it
- [x] Comics store revalidates on every visit while keeping cached data visible; failure of a background refetch keeps the cached list (no error screen over good data)
- [x] Revalidation awaits the in-flight save before fetching
- [x] Continue button with the right label and target; hidden when absent or unknown
- [x] Library unchanged
- [x] `vue-tsc` clean, vitest green

## What was built

- `web/src/api/types.ts` — `ComicDetail.continueChapterId?: string` (optional: a backend not yet deployed omits it). `client.ts` unchanged; `fetchComic` passes the field through.
- `web/src/stores/comics.ts`:
  - `load(comicId)` is now stale-while-revalidate: the cached `data` stays in the entry while `loading` is true, `await useChaptersStore().savesSettled()` runs before `fetchComic`, and a generation counter discards a late, superseded response (success or failure).
  - A failed refetch **with** cached data keeps it, sets `error: null`, and logs one `console.warn`; **without** cached data, `loading`/`error` behave as before (「載入中」 / ErrorState).
  - `entry(comicId)` / `load(comicId)` keep their signatures, so ReaderView's next-chapter lookup is unaffected (its `load` now also waits for in-flight saves, which only makes the list it reads fresher).
  - `continueChapter(comic): ChapterSummary | null` — pure; the chapter whose id is `continueChapterId`, or `null` when absent / not in the list.
- `web/src/views/ComicView.vue` — calls `store.load` on every visit (ComicView is not kept alive, so each visit remounts it). Under the header, above the list: a full-width primary `RouterLink` 「繼續閱讀 · 第 N 話」 to `{ name: 'reader', params: { comicId, chapterId } }`, `v-if` on `continueChapter`. Primary style (new; the web had none): `rounded-md bg-sky-600 px-4 py-3 text-center font-medium text-white hover:bg-sky-500`. Ticket 03's 「下一話」 button should reuse these classes.
- Library screen untouched.

## Verification done

- `npm run typecheck` (vue-tsc) clean; `npm test` 72/72 across 6 files.
  - `api/client.test.ts`: `fetchComic` decodes with `continueChapterId` and without it.
  - `stores/comics.test.ts` (new, 10 tests): first visit loading → data; revalidate keeps the cached copy visible then swaps the fresh one; refetch waits for an in-flight save (`fetchComic` not called until the PUT answers); background failure keeps cache with no error; no cache → error reported; late older success ignored; late older failure ignored; `continueChapter` found / absent / unknown id.
- `GET /comics/63d82d8f2f73a6d3` through the running dev server (`localhost:5173`, GET only): production does **not** return `continueChapterId` yet — ticket 01 is not deployed, so the button is hidden there for now, which is the "before the backend deploy" case.
- Not exercised here: the browser behaviour (checklist below is the developer's).

## Browser checklist for the developer

- [x] Before the backend deploy: chapter list works, no Continue button
- [x] After it: Continue names the chapter you're on and opens it at its resume page
- [x] Read into another chapter, go back → its badge and Continue have updated without a reload, and the list didn't flash
- [x] A comic never read → Continue points at chapter 1
