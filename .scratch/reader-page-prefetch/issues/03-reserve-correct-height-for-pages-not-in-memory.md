# 03 — Reserve the correct height for Pages that are not in memory

**What to build:** A Page whose image is not currently in memory still occupies close to its real height, so the reader's content stops being shoved around as Pages load and unload. This closes the two gaps tickets 01 and 02 leave open: a Page evicted from the cache, and a Page on the very first pass down a chapter that the reader reaches before prefetching does.

Two things make it work. First, a Page's proportions are recorded in the cache rather than in its row, so they survive both row recycling and image eviction — a Page seen once reserves its exact height forever after, image resident or not. Second, a Page never yet decoded reserves the **running median of the heights already known for that chapter**, updated as each Page decodes. Pages within one comic are consistently sized — every Page in this library is 900px wide, with heights running 8px to 2500px around a median of 1549px — so the median converges quickly and is dramatically better than today's fixed 220pt placeholder, whose under-estimate is exactly what shoves content down. A chapter with nothing decoded yet falls back to a single default until the first Page lands.

No backend, API or model change: the Scanner, the Catalog, the API contract and the iOS models are untouched. Backend-supplied Page dimensions would remove this gap entirely and are cheap to compute, but were deliberately rejected as far more surface than this problem justifies — see the spec's Out of Scope.

**Blocked by:** 02 — Prefetch a window of Pages ahead of the reader.

**Status:** reopened 2026-08-10 — implemented and accepted on device the same day, with a known residual

Device report from the repo owner: "鍵盤跳出來的時候 後面的圖片還是會上下滑動 但好多了 先這樣可以". Much improved, some movement remains, accepted as it stands.

**The residual is not diagnosed, and closing this ticket does not mean it is gone.** The likely candidate is the first pages of a chapter nothing has decoded yet, which reserve the library default rather than anything measured, and adjust once when the first real page lands — but that is a hypothesis, not a finding. Anyone picking this up again should measure before rebuilding: if the movement turns out to be concentrated at chapter openings the default is the lever, and if it is spread through a chapter the assumption that pages within a comic are consistently sized is the thing to re-check, and backend-supplied Page dimensions become the better answer after all.

**Reopened for a reason that was not on the table when it was closed.** The close below rested on the shift being cosmetic. It is not: `reader-auto-advance-false-trigger` found that the 220pt placeholder makes the reader's `contentSize` collapse by an order of magnitude when rows recycle, and the reader *infers from scroll geometry*. On an iPad, raising the keyboard to correct recognized text mid-chapter collapsed the content, which read as an overscroll past the bottom and ran the reader to the last chapter of the comic. See that spec for the full mechanism.

That feature's ticket 01 fixed the inference — auto-advance and read-detection now require a real scroll gesture, so the collapse can no longer change chapters or mark a chapter read. It deliberately did **not** fix the collapse. What remains is the reading position still shifting when it happens, which is visible on the last chapter (where the chapter change was already a no-op) and everywhere else. That is this ticket.

Re-check the assumption before rebuilding, as the original close said: the running-median approach assumes Pages within a comic are consistently sized, which held for the library measured in 2026-08 (fixed widths, predominantly 900px). A library of conventional whole pages, mixed sources, or widely varying widths would break that assumption and might make backend-supplied dimensions the better answer after all — see the spec's Out of Scope for why that was rejected the first time.

Add to the criteria below: a mid-chapter row recycle (the keyboard raised over the reader is the reproducible one) no longer moves the reading position.

### What was built, 2026-08-10

Close to the design above, with two departures worth knowing:

- The running median is **recomputed from the cache** on each visibility change rather than accumulated as pages decode. It costs a dictionary lookup per page in the chapter, and in exchange it is correct after an eviction, after a memory warning, and on re-entering a chapter read earlier in the session — none of which an accumulator would hear about. It also carries the previous chapter's median forward instead of resetting, so a chapter change never briefly un-reserves every height.
- The **failure** placeholder is deliberately left at its old fixed height. A failed page is a dead end the reader has to act on, and stranding its retry button in the middle of a screen and a half of blank space serves nobody; the shift when a retry succeeds is one the reader asked for. Only the loading/not-in-memory placeholder reserves.

Height ratios are held in a plain dictionary beside the `NSCache`, not in it — an evictable ratio would reintroduce the collapse under memory pressure, which is the worst possible moment for it.

### Original close — 2026-08-09, after device verification of ticket 02

With the prefetch window in place the repo owner scrolled a real device and reported the remaining shift as "not very noticeable", so the value of this ticket collapsed. The gap it was written to close — a Page reserving a fixed short placeholder before it has ever been decoded — is real and still present in the code, but the window now decodes nearly every Page before the reader reaches it, which leaves the gap exposed only when a reader deliberately outruns prefetching.

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
