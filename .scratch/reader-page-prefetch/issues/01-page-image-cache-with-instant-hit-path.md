# 01 — Page image cache with an instant path for images already in memory

**What to build:** A reader who scrolls back up to a Page they have already seen gets that Page instantly — no second download, and no loading placeholder frame before it appears. The Page's row is rebuilt as it always was, but the image is already in hand at the moment the row is first drawn, so the row occupies its correct height immediately and nothing shifts underneath the reader. Comic covers in the Library get the same treatment for free, so scrolling covers back into view stops re-downloading them.

Scrolling *down* is not yet improved by this ticket — nothing is fetched ahead of the reader. That arrives in ticket 02, which builds on the cache this ticket introduces.

Introduce the Page image cache as a protocol with a live implementation, injected through the SwiftUI environment the way the Reader already receives its recognizer, translator and repositories, so previews and tests can substitute their own. It is deliberately **two pieces**: a thread-safe store of decoded images that any thread can read *synchronously*, and an actor that coordinates in-flight work. The split is the whole point — reading an actor's state requires `await`, `await` cannot happen while a SwiftUI body is being evaluated, and an actor-only cache would therefore force even a guaranteed hit through the after-first-draw path that produces the flash being removed here.

`AuthorizedAsyncImage` stops issuing its own request and becomes a consumer: it performs the synchronous lookup on construction and starts in the success phase on a hit, otherwise falling back to exactly today's asynchronous path, placeholder and failure behaviour. Its phase-based content API, its decoded-image callback and its Cloudflare Access behaviour must be unchanged from every call site's point of view. Its existing static fetch function stays exactly as it is and becomes the network primitive the cache calls.

**Blocked by:** None — can start immediately.

**Status:** resolved (commit `b59d3a9`, PR [#60](https://github.com/towfd/vista_comic/pull/60), merged 2026-08-09)

Device-verified by the repo owner before merge: the no-flash guarantee, the unchanged miss path, selection/cropping at full resolution, and covers no longer re-downloading — the four criteria unit tests could not reach, since they need a rendered Reader against a running backend.

One thing worth carrying forward: this ticket alone fixed the scroll-up jitter that ticket 03 was written to address. A cached Page's first drawn frame already carries the image at full height, so nothing collapses and there is nothing for a height estimate to correct.

- [ ] Scrolling back up to a previously viewed Page shows it with no network request and no placeholder frame
- [ ] A Page image already in memory is obtainable synchronously, without `await`, from a SwiftUI body evaluation
- [ ] The synchronous lookup returns nothing for an absent URL and never triggers a fetch
- [ ] A Page not in memory loads exactly as it does today: placeholder, then success or the tappable failure placeholder
- [ ] Two concurrent asks for the same URL result in one network request
- [ ] Asking twice in sequence for the same URL results in one network request
- [ ] Images are cached at full source resolution and decoding is forced to completion off the main thread, so displaying a cached image triggers no main-thread decode
- [ ] Selection, cropping and translation behave exactly as before, and crops are still taken at full source resolution
- [ ] Retention is bounded by total decoded bytes (~150 MB); eviction *order* is explicitly not guaranteed and must not be asserted
- [ ] Everything is released on a system memory-pressure warning
- [ ] The cache is never explicitly cleared on chapter change or on leaving the Reader
- [ ] Library covers are served from the same cache and stop being re-downloaded when scrolled back into view
- [ ] Requests issued by the cache carry the Cloudflare Access headers — asserted at the cache level so a future refactor cannot lose the behaviour
- [ ] The cache is substitutable in previews and tests via the environment
- [ ] Existing `AuthorizedAsyncImage` regression tests still pass unchanged
