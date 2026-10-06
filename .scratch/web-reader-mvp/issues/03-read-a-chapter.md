# 03 — Read a chapter

**What to build:** Clicking a chapter opens the reader: the chapter's pages stacked in one continuously scrolling column, centred, at their natural width. Scrolling to the bottom reads the whole chapter. Back returns to the chapter list. **When this ticket is done, the MVP is done.**

The reader is driven by `GET /comics/{comicId}/chapters/{chapterId}`, at `/comic/:comicId/chapter/:chapterId`. Every page URL in its `pages` array passes through ticket 01's rewriting, so page images load through the proxy exactly as covers do.

**Layout follows the source rather than the window.** The library is Korean webtoon strip art — a constant 900px wide, 900 to 2500px tall per file — so there are no pages to turn and nothing to fit. Images are stacked with no gaps in a column centred at the image's natural width. They are never upscaled, which means no blur on the Vietnamese diacritics and no scaling logic at all. On a window narrower than 900px they shrink to fit rather than overflow sideways.

**Loading.** Every image carries native `loading="lazy"`, so an eighty-page chapter fetches only what is near the viewport — no observer, no prefetch code. Each image reserves its height before it arrives where the aspect ratio is known, so the column does not jump as pages land. A page that fails shows a placeholder in its slot with a retry, and the rest of the chapter is unaffected.

**What it deliberately does not do:** write or read progress (`lastReadPage` in the response is ignored), offer next-chapter navigation, prefetch, zoom, or select text. Each is either out of the MVP or a later part of the map.

**Blocked by:** 02

**Status:** done 2026-10-06 — unit-verified, checked against the live backend, and reviewed in the browser by the developer on branch `feature/web-reader-mvp`. **This completes the MVP.**

- [x] Clicking a chapter in the chapter list navigates to `/comic/:comicId/chapter/:chapterId`
- [x] All pages render in order, stacked with no gaps, in a column **at most 800px wide** — see the layout correction below
- [x] Images are never upscaled; narrower pages stay at natural size, and below 800px of window width pages shrink to fit without horizontal scrolling
- [x] Every page image uses `loading="lazy"`
- [x] Space is reserved for each image before it loads — a page-shaped 2:3 box, since the API gives no dimensions (see below)
- [x] A failed page shows an in-place placeholder with a retry; other pages are unaffected
- [x] Loading and failure-with-retry states for the chapter request itself; an unknown comic or chapter id renders not-found with a way back
- [x] Browser back returns to the chapter list; refresh keeps the reader on the same chapter
- [x] `lastReadPage` is ignored and nothing writes progress
- [x] No server, iOS, `docker-compose.yml` or `cloudflared/` file is modified

## Browser checklist for the developer

- [ ] Open a chapter and scroll to the end: every page appears, in order, with no seams between strips
- [ ] Network panel: page images arrive as you scroll toward them, not all at once on open
- [ ] On a wide window, no page is wider than 800px, and a narrow page (Conan has 446px ones) is not stretched
- [ ] Narrow the window below 800px: pages shrink, no sideways scrollbar
- [ ] Scrolling does not jump as pages finish loading
- [ ] Vietnamese lettering is as sharp as on the phone
- [ ] Opening a chapter from far down a long chapter list starts at page 1, not mid-chapter; Back returns to the same spot in the list
- [ ] Your progress on the phone has not moved after reading here

## The layout correction

The ticket and the spec assumed every page is 900px wide. Measured against the live library before building: Frieren mixes 1000×632, 1000×800 and 836×1200 in its first five pages; Hoa Son (a webtoon) is 800 wide; Conan's first chapter has 771, 777, **1890×1376** (a double-page spread), 460 and 446. "Centred at natural width" would have made the column change width on every page. Put to the developer, who chose **cap at 800px, never upscale** over stretching every page to one width or fitting each page to the window height. The spec is corrected in place.

## What was built

- `api/client.ts` — `fetchChapter`, rewriting every page URL to a path.
- `stores/chapters.ts` — one entry per `comicId/chapterId`.
- `components/ReaderPage.vue` — one page: lazy, a reserved 2:3 box until it loads, then natural size capped by the column; on failure an in-place placeholder whose retry re-requests with `?retry=n`, because the browser will not re-fetch a URL it has already failed on and the backend ignores the query.
- `views/ReaderView.vue` at `/comic/:comicId/chapter/:chapterId`; `ComicView` rows now link to it.
- `router.ts` — a `scrollBehavior` (see below).

## Two traps this ticket had to avoid

- **Lazy loading needs reserved height.** The API returns no page dimensions, so an unloaded image is zero pixels tall. Forty zero-height images all sit at one spot, all "near the viewport", and `loading="lazy"` fetches the whole chapter at once — the feature silently does nothing. Each page therefore holds a 2:3 box until it loads.
- **The router keeps the previous scroll offset by default.** Opening chapter 800 from Conan's list would have opened the reader mid-chapter. Forward navigation now starts at the top; Back and Forward restore the saved position.

## A known limit, not fixed

Because the reserved box is a guess (2:3) rather than the page's real shape, a page that loads *above* the viewport changes height and can nudge what you are looking at. In normal top-to-bottom reading this does not arise, since lazy loading fetches pages well before they scroll into view; it shows up when jumping far down quickly. Chrome and Firefox's scroll anchoring compensates. The real fix is page dimensions from the API — `.scratch/page-dimensions/` is a parked spec for exactly that, and it is a server change, so it is out of this MVP.

## Verification done

- `vue-tsc` clean; 19/19 unit tests (3 new: page rewriting in order, encoded ids, 404 → `notFound`).
- Live, through the proxy: a chapter detail and its pages load; a page URL with `?retry=1` → 200 `image/jpeg`; a reader URL requested as HTML → 200, so refresh works; an unknown chapter → 404 `Chapter not found`.
- `lastReadPage` is typed, documented as ignored, and read nowhere. No code path writes progress.
