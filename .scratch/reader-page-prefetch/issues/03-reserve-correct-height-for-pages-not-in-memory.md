# 03 — Reserve the correct height for Pages that are not in memory

**What to build:** A Page whose image is not currently in memory still occupies close to its real height, so the reader's content stops being shoved around as Pages load and unload. This closes the two gaps tickets 01 and 02 leave open: a Page evicted from the cache, and a Page on the very first pass down a chapter that the reader reaches before prefetching does.

Two things make it work. First, a Page's proportions are recorded in the cache rather than in its row, so they survive both row recycling and image eviction — a Page seen once reserves its exact height forever after, image resident or not. Second, a Page never yet decoded reserves the **running median of the heights already known for that chapter**, updated as each Page decodes. Pages within one comic are consistently sized — every Page in this library is 900px wide, with heights running 8px to 2500px around a median of 1549px — so the median converges quickly and is dramatically better than today's fixed 220pt placeholder, whose under-estimate is exactly what shoves content down. A chapter with nothing decoded yet falls back to a single default until the first Page lands.

No backend, API or model change: the Scanner, the Catalog, the API contract and the iOS models are untouched. Backend-supplied Page dimensions would remove this gap entirely and are cheap to compute, but were deliberately rejected as far more surface than this problem justifies — see the spec's Out of Scope.

**Blocked by:** 02 — Prefetch a window of Pages ahead of the reader.

**Status:** not doing — closed 2026-08-09 after device verification of ticket 02

**Do not pick this up off the frontier.** With the prefetch window in place the repo owner scrolled a real device and reported the remaining shift as "not very noticeable", so the value of this ticket collapsed. The gap it was written to close — a Page reserving a fixed short placeholder before it has ever been decoded — is real and still present in the code, but the window now decodes nearly every Page before the reader reaches it, which leaves the gap exposed only when a reader deliberately outruns prefetching.

Reopen this only if that changes, and check the assumption before rebuilding: the running-median approach assumes Pages within a comic are consistently sized, which held for the library measured in 2026-08 (fixed widths, predominantly 900px). A library of conventional whole pages, mixed sources, or widely varying widths would break that assumption and might make backend-supplied dimensions the better answer after all — see the spec's Out of Scope for why that was rejected the first time.

- [ ] Scrolling down a brand-new chapter faster than prefetching keeps up no longer shoves content down as Pages arrive
- [ ] A Page whose image has been evicted still reserves its correct height when its row is rebuilt
- [ ] Proportions remain available for a URL whose image is no longer resident
- [ ] A Page with known proportions reserves its exact height from the moment its row is built
- [ ] A Page not yet decoded reserves the running median of the heights known for that chapter
- [ ] The median updates as each Page decodes within the chapter
- [ ] A chapter with nothing decoded yet uses a single default, and the reader behaves sensibly on the very first Page
- [ ] Height reservation is verified as pure logic — known proportions, unknown Page with a populated chapter, and empty chapter — without rendering
- [ ] Resume-to-page, chapter-bottom detection and pull-past-end chapter advance all still work
- [ ] No change to the Scanner, the Catalog, the API contract or the iOS models
