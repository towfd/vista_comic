Status: ready-for-agent

# Page dimensions: stop guessing how tall a page is

## Problem Statement

The Reader's content moves underneath the reader, and it has done since before zoom existed.

A page that has not been decoded yet has no idea how tall it is, so its row reserves the running median height of the pages already decoded in that chapter. That estimate replaced a fixed short placeholder and was a large improvement, but it is an average over a library that has no typical page. Measured against the real files: **height-to-width ratios run from 0.01 to 3.62** against a fixed 900px width — a sliver nine pixels tall at one end and a page over 3200px at the other. The tallest page is more than twice the median. No single estimate can serve both ends; the median is not occasionally wrong, it is guaranteed to be badly wrong for the extremes.

When the image finally arrives, the row snaps to its real height. If that row is above the reader, everything below it moves and the reader is shoved down the chapter.

This was found, understood, and deliberately closed once already. `reader-page-prefetch` ticket 03 shipped the remembered-proportions half and closed the estimate half as **not doing**, on the evidence that with prefetching in place the residual shift was "not very noticeable" on a device. Its own note recorded the condition for revisiting: re-check the assumption that pages within a comic are consistently sized, and consider backend-supplied dimensions if it fails.

**Zoom is what made it fail.** Magnification multiplies the error along with the page: a page mis-reserved by ~400pt at full width on a 393pt phone is mis-reserved by ~1200pt at 3x. The repo owner's verdict after reading on a real device was that the reader jumped around constantly and the experience was bad. The estimate is not a zoom defect, but zoom took it from tolerable to unusable.

Independent research into how this is solved elsewhere (`research-scroll-anchoring-and-zoom.md`, under `.scratch/reader-zoom/`) reached the same conclusion from the other direction. Apple's guidance for a view that resizes after it appears is not to compensate for the movement but to stop being wrong about the height in the first place; and SwiftUI has no equivalent of UIKit's content-offset adjustment, so compensation is not available to be built cheaply anyway. One backend field replaces an unbounded amount of client-side anchoring machinery.

## Solution

The scanner measures **nothing**. Rescan stays exactly as fast as it is today, which matters because the library is past three thousand chapters and a rescan is a pull-to-refresh the reader waits on.

Instead, pages are measured **where they are about to be read**. Opening a chapter measures that chapter, and a sliding window measures the chapters around it in the background — one behind and three ahead — so that continuing to read never waits again. Nothing is ever measured for the thousands of chapters the reader is not near.

Measuring reads image headers only; the pixels are never decoded.

**The wait lands where a wait is already happening.** The chapter endpoint answers only once it has measured, subject to a hard five-second ceiling. That delay falls on the loading indicator the Reader already shows while a chapter opens — and because no page has been drawn yet, **there is nothing on screen that can jump**. Every row is laid out at its exact height from its very first frame. A wait at a transition is a different thing from instability during reading, even when the seconds are the same.

The sliding window means that wait happens **once per comic**, not once per chapter. From the second chapter onward — including pulling past the bottom to auto-advance — the ratios are already in hand and the response carries them for free.

**Ratios are applied only when a chapter loads, and never afterwards.** This is what removes the whole class of "corrected too late" problems: there is no arrival event to handle, no compensation to compute, no re-anchoring, because nothing ever arrives after the layout exists. If the five-second ceiling is hit, the pages it did not reach fall back to today's estimate for that one read; the background window finishes them, and the next open of that chapter is exact.

Measurements are held in memory, keyed by the page's own path, so they survive a rescan and adding a comic never invalidates another one. Nothing is written to disk and no schema changes.

## User Stories

1. As a reader, I want a page to occupy its correct height before its image arrives, so that content above me does not shove me down the chapter as it loads.
2. As a reader scrolling faster than pages can load, I want my position to stay put, so that outrunning the prefetcher is not punished.
3. As a reader who has magnified the page, I want the same stability, so that zoom does not multiply a shift into something unusable.
4. As a reader, I want my position held when rows are rebuilt — the keyboard over the reader, a rotation, a memory warning — so that the app never loses my place for reasons I cannot see.
5. As a reader, I want pulling to refresh to be exactly as fast as it is today, so that fixing the jumping does not cost me the library screen.
6. As a reader opening a comic, I want any wait to happen before the page appears rather than while I read, so that I am never reading something that is moving.
7. As a reader, I want that wait to be bounded, so that a slow disk cannot leave me staring at a spinner.
8. As a reader continuing to the next chapter, I want no wait at all, so that reading several chapters in a row is uninterrupted.
9. As a reader who auto-advances past the end of a chapter, I want the next chapter to open as immediately as it does today.
10. As a reader, I want a chapter the backend could not measure to behave no worse than it does today, so that an odd file costs one page rather than the chapter.
11. As a reader, I want measuring not to compete with loading the pages I am actually looking at, so that the fix does not make images slower.
12. As a reader who flips quickly through the chapter list, I want abandoned chapters to stop being measured, so that browsing does not leave the server working on chapters I passed.
13. As a reader, I want the app to keep working against a backend that does not send dimensions, so that the two can be updated in either order.
14. As the developer, I want the library scan unchanged, so that starting the backend is no slower with three thousand chapters than it is now.
15. As the developer, I want an unreadable page reported rather than fatal, so that one bad file cannot take out a comic.
16. As the developer, I want the measurement verified against real files rather than assumed, so that the fix is known to address the measured spread.

## Implementation Decisions

### The scanner does not measure

Measurement is removed from the library walk entirely. The scan's cost is unchanged, and this is load-bearing rather than an optimisation: at this library's size a rescan is already a ten-second-plus operation that the reader triggers by pulling to refresh and then waits on, and measuring every page during it was measured on a stand-in library to cost roughly 0.43ms per page — an addition that scales with the whole library rather than with what is being read.

### Measurement follows the reader

- Opening a chapter measures **that chapter**, and the response waits for it.
- A **hard ceiling of five seconds** bounds that wait. Pages not reached in time are reported as unknown and fall back to the client's existing estimate.
- Measuring is parallel across pages, since it is I/O-bound and the ceiling is a wall-clock budget.
- After the response is sent, a **window** of the previous chapter and the next three is measured in the background.
- **The newest window replaces the pending one** rather than queueing behind it, so flipping quickly through chapters cannot accumulate work for chapters that were passed.
- **One chapter is measured at a time.** Measurement competes for the same disk as the page images the reader is waiting on, which is the failure that would present as "images got slower" rather than as anything recognisably about measurement.
- Measuring a chapter is **interruptible between pages**, so a replaced window stops promptly.
- **Nothing measured is ever discarded.** A cancelled chapter keeps whatever it completed; the next visit continues from there.
- A page whose dimensions cannot be read is recorded as unknown, keeps its position, and is reported through the existing scan-report channel rather than failing anything.

Opening a *comic* — as distinct from a chapter — deliberately does not trigger measurement. It would buy the human's chapter-choosing time as lead-in, but at the cost of working on chapters for a comic that was only glanced at.

### What is stored

- **Memory only.** No disk cache, no database, no schema change.
- **Keyed by the page's path**, not by chapter. A rescan therefore invalidates nothing, and adding a comic does not cause any other chapter to be measured again. A path that no longer matches simply gets measured; the store cannot serve a stale answer for a page that changed identity.
- Roughly one number per page ever read, which is negligible beside a single decoded page.

### The contract gains one parallel array

The chapter reader response gains a list of **height-over-width ratios**, in the same order and of the same length as its existing page list, with a null for any page that could not be measured or that the ceiling cut short.

- Parallel to the page list rather than a reshaping of it, so the app and the backend can be updated in either order and an app that ignores the field behaves exactly as it does today.
- Ratios rather than pixel dimensions, because height-over-width is what the client's reserved-height calculation already speaks. Nothing on either side has a use for the absolute numbers that the source image does not already answer.
- **A list whose length does not match the page list is ignored in its entirety** by the client. The contract pairs by position, so a mismatch means the pairing cannot be trusted — and reserving confidently wrong heights is worse than reserving estimated ones.

### The client is told, rather than only ever learning

The image cache already remembers a height ratio per page URL, already outlives both row recycling and image eviction, and is already consulted while a row is being described. Its one gap is that a ratio could only be learned by decoding an image. It gains a single operation: be told ratios for URLs.

The Reader seeds them when a chapter's pages load, in the same step that seeds the prefetch window — and **only** there. A ratio already on record is never replaced by a told one, so what the cache actually holds always wins over what it was told.

Everything downstream is untouched: the reserved-height calculation, the chapter median, the row placeholder, and the rule that ratios are never evicted all keep working exactly as they do, and simply start having an answer for pages that have never been on screen. The median degrades to what it should always have been — the fallback for a page nobody could measure.

## Testing Decisions

Assert on what a caller observes — what the endpoint returns, what the cache answers, which requests were made — never on how the store is shaped.

**Backend.** The existing scanner tests build a temporary library tree under a temp path and need no database, so they run in this environment; follow that shape. Note that the shared fixtures deliberately write non-image bytes, so anything asserting on real dimensions must write real images.

- A chapter of pages of known, differing sizes reports the matching ratios, in reading order.
- The ratios list is always the same length as the page list.
- A page that cannot be read reports an unknown ratio in its position, does not fail, and leaves the pages around it correct.
- A chapter's own cover is excluded from the ratios exactly as it is from the pages.
- The ceiling is honoured: a chapter that cannot be measured in the budget still answers, with unknowns for what was not reached.
- A second request for an already-measured chapter does no file reading at all.
- The window measures the previous chapter and the next three, and no others.
- A new window replaces a pending one rather than queueing after it.
- Only one chapter is measured at a time.
- A cancelled chapter keeps the pages it had already measured.
- The scan itself performs no measurement — asserted directly, because this is the property that keeps rescan fast and it would regress silently.

The reader endpoint's own tests cannot be run in this environment: this machine's native Postgres shadows the docker-compose one, a pre-existing and documented limitation. Verify the response shape by exercising the live containerised service, and take particular care that the null entries survive serialisation — a serialiser that strips nulls from inside the array would break the length agreement the contract depends on, and the client would then discard the whole list.

**iOS.**

- Ratios are paired with their pages by position.
- A page reported as unmeasured is skipped without disturbing the pairing of the pages after it.
- Lists of differing lengths seed nothing at all.
- A backend that sends no ratios seeds nothing and is not an error.
- A seeded page reports its proportions without its image ever being fetched.
- A ratio already on record is not replaced by a seeded one.
- A seeded page reserves its exact height rather than the chapter median.

**No XCUITest is written**, per this repo's verification rules. The device checklist is the deliverable for the behaviour itself, and it is the entire point of the feature: open a chapter never read before and scroll down faster than the pages can load, at full width and again magnified, and confirm the content does not shove.

## Out of Scope

- **Measuring during the library scan**, in any form, including incrementally.
- **Persisting measurements** — no database column, no disk cache. Both were considered: the database was rejected for making Postgres hold catalog data that could then disagree with the filesystem, and the disk cache for buying only "the first chapter after a restart is instant" in exchange for a file format, an invalidation rule and corrupt-file handling.
- **Warming on comic open** rather than chapter open.
- **Reshaping the page list into objects**, or any other breaking contract change.
- **Sending absolute pixel dimensions.** Revisit only when something needs them.
- **Using dimensions for anything but reserving height** — no downsampling, no cache budgeting, no layout decisions.
- **The Reader's failure placeholder**, which is deliberately not height-reserved and stays that way.
- **Applying ratios to a chapter that is already on screen.** The invariant that they only ever apply at load is what makes this feature small.

## Further Notes

**What is measured, and what is extrapolated.** The per-page cost (~0.43ms) and the ratio range (0.01–3.62) were measured on the library this development machine has: 19 chapters, 1855 pages, 175 MB. **That is not the repo owner's library.** Theirs is past three thousand chapters and is not on this machine — the backend may have moved to another host. Every statement here about wall-clock cost at their scale is therefore an extrapolation from a stand-in two orders of magnitude smaller, and an earlier version of this work was built on exactly that mistake: measuring the stand-in, describing it as the real library, and designing a scan-time measurement that would have taken roughly two minutes per rescan.

The design is shaped so that being wrong about this again is survivable rather than fatal. Nothing is measured that is not about to be read, and the one wait that exists has a ceiling the reader chose. If the disk is far slower than extrapolated, the symptom is that the ceiling is reached and some pages fall back to estimates — the same behaviour as today — rather than a rescan that takes minutes.

**The first thing to check on a device** is how long that opening wait actually is. If it routinely approaches five seconds, the extrapolation was wrong and the response is to narrow the window or raise the parallelism, not to move the measurement back into the scan.

**Why this is worth building whichever way the zoom architecture goes.** If the Reader stays in SwiftUI, exact heights are the fix — Apple's own guidance for a view that resizes after it appears is to stop being wrong about the height, and SwiftUI has no offset-adjustment mechanism to compensate with. If the pages strip is later ported to a UIKit collection view, exact heights are what let its layout compute the whole content coordinate system upfront and skip the content-offset-adjustment machinery entirely — the hardest part of that port. It is the one piece of this work that is not wasted either way.
