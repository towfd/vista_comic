# 04 — Chapter list stays fresh and offers Continue

**What to build:** The chapter list reflects what was just read, and gets a 「繼續閱讀 · 第 N 話」 button. Rules are in the spec's "Chapter list freshness" and "Continue button" sections:

- **Stale-while-revalidate**: every visit renders the cached comic detail at once and refetches `GET /comics/{comicId}` in the background; no flash, no 「載入中」 when a cached copy exists.
- **The refetch waits for any in-flight progress save** (ticket 02's observable save), so badges include the chapter just left.
- **Continue**: under the title, above the chapters, primary style; N = `number` of the chapter whose id is `continueChapterId`; opens the reader normally (resumes at `lastReadPage`). Always shown — with no progress it points at chapter 1.
- **Hidden when `continueChapterId` is absent or not in the list**, so this can merge before ticket 01 is deployed.
- The library screen is unchanged.

**Blocked by:** 01, 02

**Status:** ready

- [ ] `types.ts`: `ComicDetail.continueChapterId?: string`; client decoding unit-tested with and without it
- [ ] Comics store revalidates on every visit while keeping cached data visible; failure of a background refetch keeps the cached list (no error screen over good data)
- [ ] Revalidation awaits the in-flight save before fetching
- [ ] Continue button with the right label and target; hidden when absent or unknown
- [ ] Library unchanged
- [ ] `vue-tsc` clean, vitest green

## Browser checklist for the developer

- [ ] Before the backend deploy: chapter list works, no Continue button
- [ ] After it: Continue names the chapter you're on and opens it at its resume page
- [ ] Read into another chapter, go back → its badge and Continue have updated without a reload, and the list didn't flash
- [ ] A comic never read → Continue points at chapter 1
