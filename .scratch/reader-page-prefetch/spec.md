Status: ready-for-agent

# Reader page prefetch: pages that are already there when you reach them

## Problem Statement

Reading a comic in the Reader is a stop-start experience.

**Scrolling down means waiting.** Every Page begins loading only at the moment it enters the viewport — the request goes out, travels through the tunnel, comes back, and only then is the image decoded and shown. Nothing is fetched ahead. The individual wait is not long, but it happens on *every* Page, so the reader is repeatedly interrupted by a loading indicator mid-scroll. Reading a chapter never settles into a rhythm.

**Scrolling up means the page jumps.** The Reader's vertical stack is lazy, so a Page that leaves the viewport is destroyed along with everything it had loaded. Scrolling back up re-creates it from nothing: the image is fetched over the network *again*, and until it arrives the Page occupies a short placeholder instead of its real height. The stack's total height therefore changes underneath the reader as they scroll, and the scroll position lurches. It is worst going up, because the content that changes size is above the viewport and shoves everything down.

Underneath both symptoms is the same gap: **there is no cache anywhere in the Page image path.** The shared URL cache the networking layer falls back on is far too small for Page-sized images and the backend sends no caching directives, so in practice every appearance of a Page is a fresh download and a fresh full-resolution decode.

There is a third, subtler cause of the same felt problem. Today a Page image is requested from inside a task that SwiftUI runs *after* the row has already been drawn once. That first draw necessarily shows the loading placeholder — so even a Page whose bytes were already in hand would still flash before it appeared. Any fix that only removes the network round trip would leave that flash in place, and the flash is a real part of what "always loading" feels like when rows are being built continuously during a scroll.

## Solution

Give the Reader a **sliding window of Pages that are fetched and decoded before the reader arrives at them**, and make a Page that is already in hand appear **without any intermediate state at all**.

When a chapter opens, the Reader seeds the window at the Page it is actually going to show — the resume position, an explicit target page from a history jump, or the first Page on an auto-advance — and begins loading that Page plus the next five. As the reader scrolls, the window slides with them, keeping five Pages ahead and two behind. Measured against the real library, five Pages ahead is a median of **4.2 screens** of content, comfortably more than normal scrolling consumes.

Crucially, an image that is already cached is read **synchronously, while the row is being described**, so the row's very first drawn frame contains the image. No placeholder frame, no flash — scrolling into an already-prefetched Page looks like the Page was simply always there. A Page that is *not* cached falls back to exactly today's asynchronous path with today's placeholder and failure behaviour.

Retention is bounded by total decoded bytes rather than by a Page count. Because every Page in this library is the same width, a Page's decoded size is proportional to its on-screen height, so a byte budget is automatically a consistent budget of *reading distance* — it self-adjusts between a run of tall Pages and a run of thin slices, with no height arithmetic anywhere.

**Shipped status (2026-08-09): the height-reservation half below was not built.** Tickets 01 and 02 shipped in PR #60. The synchronous hit path turned out to fix the reported scroll-up jitter on its own — a cached Page's first drawn frame already carries the image at its full height, so nothing collapses — and with prefetching in place the repo owner judged the remaining first-pass shift "not very noticeable" on a real device. Ticket 03 is closed as not-doing; user stories 8 and 9 are therefore unmet by design, not by oversight. The rest of this section describes what was designed, and remains the plan if that judgement ever reverses.

The jitter is addressed separately: **once a Page's proportions are known they are remembered for the rest of the session**, in the cache rather than in the row, so they survive both row recycling and image eviction. A Page whose image is no longer resident still reserves its correct height. A Page never yet seen reserves the running median height of the Pages already decoded in that chapter, which is far closer than today's fixed short placeholder.

No backend, API, or model change is required.

## User Stories

1. As a reader, I want the pages just below me to be already loaded when I scroll to them, so that reading is continuous instead of stop-start.
2. As a reader, I want an already-loaded page to appear with no loading flash at all, so that scrolling feels like the page was always there.
3. As a reader, I want a chapter to start fetching the moment I open it, so that the first page is not the slowest one.
4. As a reader who resumes mid-chapter, I want prefetching to start at the page I actually resume to, so that resuming is not slower than starting from the beginning.
5. As a reader who jumps to a page from a history record, I want that page and the ones after it prefetched, so that arriving by a jump feels the same as arriving by scrolling.
6. As a reader, I want pages I just scrolled past to still be there when I scroll back up, so that re-reading a panel costs nothing.
7. As a reader, I want the scroll position to stay put when I scroll up, so that the page I am looking at does not slide out from under me.
8. As a reader, I want a page whose image is not resident to still occupy its correct height, so that the reader never jumps as content loads or unloads around me.
9. As a reader, I want a page I have never seen to reserve a sensible height rather than a tiny one, so that the first pass down a chapter does not shove content around.
10. As a reader, I want the reader to stay responsive while pages load in the background, so that prefetching never makes scrolling stutter.
11. As a reader, I want the page I am actually looking at to be prioritised over pages being prefetched, so that background work never delays what is on screen.
12. As a reader, I want a fast scroll through many pages not to leave a queue of stale requests running, so that the pages I land on are not stuck behind pages I already passed.
13. As a reader on a long chapter, I want the app's memory use to stay bounded, so that reading a hundred-page chapter does not get slower or destabilise my phone.
14. As a reader, I want cached pages released if the system runs short of memory, so that reading never puts the device under pressure.
15. As a reader who switches to the previous or next chapter, I want the pages I just read to still be cached, so that flipping back and forth is instant.
16. As a reader who leaves a chapter and comes back, I want it to open where I left off without re-downloading, so that stepping out of the reader is cheap.
17. As a reader who auto-advances past the end of a chapter, I want the next chapter to start prefetching as soon as it opens, so that the seam between chapters is not the slowest part of reading.
18. As a reader with no connection, I want the app not to keep hammering a page that failed, so that a dead network does not drain my battery.
19. As a reader, I want a page that failed to still be retryable by tapping it, so that a transient problem is not permanent.
20. As a reader, I want a retry to actually re-request the page rather than replay the same failure, so that retrying means something.
21. As a reader, I want the existing loading and failure placeholders to keep working for pages that genuinely are not loaded, so that I can still tell "loading" from "broken".
22. As a reader, I want text selection and translation to keep working exactly as before, so that a performance change does not cost me the feature I read with.
23. As a reader, I want a crop taken from a cached page to be at full source resolution, so that recognition quality is unchanged by caching.
24. As a reader, I want my reading progress to keep being saved as I scroll, so that prefetching does not disturb where the app thinks I am.
25. As a reader, I want prefetching never to move my saved position, so that pages loaded ahead of me are never mistaken for pages I have read.
26. As a reader on a preview (peek) open, I want prefetching to behave the same, so that previewing a page is as smooth as normal reading.
27. As a reader, I want the same page requested twice at once to be fetched only once, so that scrolling quickly does not multiply my network traffic.
28. As a reader behind Cloudflare Access, I want prefetched requests authenticated like every other request, so that prefetching does not silently fail at the edge.
29. As a reader on the library screen, I want covers to stop being re-downloaded every time they scroll back into view, so that browsing is smooth too.
30. As a developer, I want the caching and prefetching behaviour testable without rendering the reader, so that it can be verified quickly and reliably.
31. As a developer, I want to substitute the cache in previews and tests, so that screens can be exercised without the network.

## Implementation Decisions

### A Page image cache — the single new seam

One new component owns fetching, decoding, retention and window management for Page images. It is defined as a protocol with a live implementation and injected through the SwiftUI environment, following the pattern the Reader already uses for the recognizer, the translator and the repositories, so previews and tests substitute their own.

It is deliberately **two pieces**, not one actor:

- **A synchronously readable store of decoded images.** A thread-safe container (`NSCache` is thread-safe by contract) that any thread — including the main thread mid-layout — can look up without `await`.
- **An actor that coordinates work**: what is in flight, who is waiting on what, which URLs the window wants, and cancellation.

The split exists for one reason, and it is the reason the feature achieves its goal: **reading an actor's state from outside always requires `await`, and `await` cannot happen while a SwiftUI view's body is being evaluated.** An actor-only cache would force even a guaranteed hit through the after-first-draw path, which is precisely the flash being removed. The cost is that the store's thread safety is its own responsibility rather than the actor's; that is accepted.

External surface:

- **Look up a decoded image synchronously.** Returns it if resident, `nil` otherwise. Never blocks, never fetches.
- **Get an image asynchronously.** Resident → returns at once; otherwise fetches, decodes, stores. Two concurrent asks for the same URL share one fetch.
- **Set the prefetch window.** Given the chapter's ordered Page URLs and the reader's current index, start what is missing, cancel what has left the window, and mark out-of-window entries evictable.
- **Ask for a URL's known proportions.** Available for any URL decoded this session, whether or not its image is still resident.

### The image view becomes a consumer

`AuthorizedAsyncImage` stops issuing its own request. On construction it performs the synchronous lookup and, on a hit, starts in the success phase — so the first frame it draws is the image. On a miss it behaves exactly as today: placeholder first, asynchronous load, then success or failure.

Its phase-based content API, its decoded-image callback, and its Cloudflare Access behaviour are unchanged from every call site's point of view. Its existing static fetch function stays exactly as it is and becomes the network primitive the cache calls, so the authentication behaviour and its regression tests survive untouched.

Covers use the same view and therefore gain the cache for free. A cover decodes to roughly 0.2 MB, so no special-casing or separate budget is warranted. Only the *window* is Reader-specific; the cache is keyed by URL and has no opinion about what an image depicts.

### The window

- **Current Page, five ahead, two behind.**
- Seeded at the Page the Reader will actually display on open — the resume position, an explicit target page, or the first Page on an auto-advance restart — not unconditionally at the first Page.
- Re-centred on the top-most visible Page.
- At most four fetches run concurrently. The library's Pages average 94 KB, so the cost of a fetch is almost entirely round-trip latency; four in flight hides that latency without saturating the connection or the decoder.
- A request for the Page the reader has actually reached takes priority over prefetches further down.
- Requests for Pages that leave the window are cancelled rather than left to complete.
- Chapter changes re-seed the window; they do **not** clear the cache.

### Retention

- Memory only. Nothing is written to disk.
- Bounded by total decoded bytes — approximately 150 MB. The window itself is roughly 45 MB; the remainder absorbs scrolling back, chapter switching and covers.
- **Eviction order is deliberately not guaranteed.** The store is an `NSCache`, whose eviction order is documented as unspecified (approximately least-recently-used in practice). What is guaranteed, and what is tested, is that the byte budget is respected. Ordering was considered and rejected: at a 150 MB budget against a 45 MB window, eviction is rare in the first place, and when it does happen what matters is that memory stays bounded rather than which Page went first. Guaranteeing order would mean replacing `NSCache` with a hand-rolled lock-guarded LRU and giving up its built-in response to memory pressure — a poor trade for a property no caller depends on. No test may assert which particular entry was evicted.
- **No explicit clearing on chapter change or on leaving the Reader.** The byte budget makes those rules unnecessary, and dropping them is what makes flipping between adjacent chapters, and leaving and re-entering a chapter, instant.
- Everything is released on a system memory-pressure warning.
- Images are cached at **full source resolution**. The selection-crop path reads source pixels, so downsampling would silently degrade recognition quality; that trade is not taken.
- Decoding is forced to completion off the main thread inside the cache, so displaying a cached image never triggers a main-thread decode at draw time. This is part of the win, not an optimisation detail: today that decode happens during rendering.

### Failures

- A failed URL is **marked as failed and not retried automatically**. Without this, the window reconciler would see "not resident, not in flight", re-request immediately, fail again, and loop — turning a dead network into a request storm that burns CPU and battery.
- The mark is cleared by an explicit retry, or by the reader actually scrolling to that Page. Prefetch alone never re-attempts it.
- The Reader's existing behaviour — a failed Page shows a tappable placeholder, and tapping retries every currently-failed Page — is preserved and routes through the cache.

### Reserved page height

- Proportions live in the cache, not in the row, so they survive both row recycling and image eviction. A Page with known proportions reserves its exact height from the moment its row is built.
- A Page not yet decoded reserves the **running median of the heights already known for that chapter**, updated as each Page decodes. Pages within one comic are consistently sized (every Page in this library is 900px wide), so the median converges quickly and is dramatically better than the current fixed short placeholder, whose under-estimate is what shoves content down on a first pass.
- A chapter with nothing decoded yet uses a single default until the first Page lands.
- No backend change: the Scanner, the Catalog, the API contract and the iOS models are untouched.

### Progress reporting stays separate

The window and progress reporting consume the same "which Pages are visible" signal but must behave oppositely: the window reacts immediately, progress stays debounced, and **prefetching must never cause a progress write**. Keep the two paths visibly distinct rather than sharing a convenience helper that quietly does both — a prefetched Page being counted as read is the most damaging failure this feature could introduce.

## Testing Decisions

A good test here asserts on **what the outside world observes** — which URLs were requested, how many times, in what order, and what the cache hands back — never on how retention is implemented internally. No test should assert that a particular container holds a particular key.

**Prior art:** `AuthorizedAsyncImageTests` and `APIComicRepositoryTests` each stand up a file-private `URLProtocol` stub over an ephemeral session, serve canned bytes, and assert on the request seen. That is the right shape here, extended to record *every* request and to serve per-URL bodies. Keep the stub file-private, per the existing note about parallel suites racing on shared static state.

**The cache is the module under test**, and nearly everything is verifiable there without rendering a view:

- Asking twice for the same URL issues one network request; the second is served from memory.
- Two concurrent asks for the same URL issue one request.
- After an image is resident, the **synchronous** lookup returns it — this is the assertion that protects the no-flash guarantee, and it must be a real test, because losing it would silently restore the old behaviour with everything else still passing.
- The synchronous lookup returns `nil` for an absent URL and never triggers a fetch.
- Setting a window at index *n* requests exactly that Page and the five after it, and nothing else.
- Sliding the window forward requests only newly-entered Pages, not ones already resident.
- A window seeded mid-chapter starts at that index, not at the first Page.
- A window near the end of a chapter clamps instead of requesting past the last Page.
- Pages leaving the window are cancelled and stop consuming in-flight capacity.
- No more than four fetches are in flight at once.
- A failed URL is not re-requested by a subsequent window reconcile — the anti-storm guarantee.
- An explicit retry does re-request a previously failed URL.
- Proportions remain available for a URL whose image has been evicted.
- Requests carry the Cloudflare Access headers — assert once at the cache level so a future refactor cannot lose the behaviour the existing view-level tests protect.

**Height reservation** is tested as pure logic: known proportions plus an available width produce the reserved height; an unknown Page produces the running median of the known ones; an empty chapter produces the default.

**Reader-level behaviour** that genuinely needs the view — that prefetching does not trigger a progress write, and that a chapter change re-seeds the window without clearing the cache — is covered by driving the Reader's window and progress logic with a substituted cache, following how `SelectionEnqueueFlowTests` and `HistoryActionsTests` exercise reader-owned logic with test doubles.

**UI tests:** per this repo's verification rules, write XCUITest coverage for the reader scroll path as part of the increment and build-verify that it compiles, but hand off actually running it — the simulator here cannot initialise the accessibility runner.

## Out of Scope

- **Disk caching.** Nothing survives app launch. Considered and deliberately deferred: the win being chased is the sliding window, and a disk layer adds capacity limits, eviction and invalidation for a benefit that is not the reported problem.
- **Backend-supplied Page dimensions.** Reading each Page's width and height at scan time and returning them would remove the first-load reserve gap entirely and is cheap to compute (measured: 696 ms for the whole 1855-file library, since only image headers are read, and Pillow is already a backend dependency). It is nonetheless out of scope because it changes the Scanner, the Catalog model, the API contract, the iOS model and the API documentation — far more surface than this problem justifies. The running-median estimate plus prefetch covers the observed symptom. Revisit only if first-pass jitter survives this work.
- **Screen-height-based window sizing.** Considered, because Page heights in this library vary 64-fold. Rejected as unnecessary: bounding retention by decoded bytes already yields a consistent reading-distance budget without needing any height known in advance.
- **Downsampled or server-side resized images.** Would cut memory and decode cost, but conflicts with full-resolution crops. Revisit only if memory proves to be the binding constraint, and by lowering the retention budget first.
- **Whole-chapter preloading / offline reading.** Explicitly rejected in favour of the window.
- **Prefetching into the next chapter before the reader reaches the end.** The window stops at the chapter boundary.
- **Cache-Control headers on the media endpoints.** A cheap backend win, but the in-memory cache makes it moot here; revisit alongside a disk layer.
- **Prefetching covers in the library grid.** Covers gain the cache by sharing the image view; no window logic is added for them.
- **Any change to progress reporting, selection, translation, or comprehension behaviour.**

## Further Notes

The decisions above rest on measurements of the actual library rather than assumptions, and re-measuring is worthwhile if the library's character changes:

- 1855 Pages, average 94 KB, maximum 538 KB. **Fetch cost is round-trip latency, not bandwidth** — which is why concurrency matters more than request size.
- Every Page is one of a few fixed widths (predominantly 900px); heights run from 8px to 2500px, median 1549px. This library is webtoon-style vertical slices, not conventional whole pages. Height varies 64-fold; width does not vary meaningfully.
- Because width is fixed, decoded bytes are proportional to on-screen height. This is the property that lets a byte budget stand in for a reading-distance budget.
- Five Pages ahead is a median of 4.2 screens of content (10th percentile 3.1). Ten Pages ahead would be 8.3 screens — measurably more memory and connections for a buffer the reader will not outrun in normal use.
- The eight in-window Pages are roughly 45 MB decoded at the median.

Two things to watch during implementation. The first is the window/progress separation described above. The second is memory: if a device turns out not to tolerate the retention budget, the correct response is to **lower the budget** — the cache may hold fewer images than the window prefetches — not to silently downsample and damage crop quality.

Verification should cover one compact-phone and one larger-phone layout, and should specifically exercise: opening a chapter mid-chapter via resume, scrolling down through a long chapter, scrolling back up several pages, switching to the previous chapter and back, and leaving the Reader and re-entering the same chapter.
