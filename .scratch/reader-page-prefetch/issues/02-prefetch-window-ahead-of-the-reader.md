# 02 — Prefetch a window of Pages ahead of the reader

**What to build:** On a normal connection, scrolling down a chapter stops showing loading indicators. The Pages just below the reader have already been fetched and decoded by the time they are reached, so — combined with ticket 01's instant hit path — arriving at a Page simply shows the Page.

When a chapter opens, the Reader seeds a window at the Page it is actually going to display — the resume position, an explicit target page from a History jump, or the first Page on an auto-advance restart — never unconditionally at the first Page. The window covers the current Page, five ahead and two behind, and slides as the reader scrolls. Measured against the real library, five Pages ahead is a median of 4.2 screens of content.

A fast scroll must stay responsive: requests for Pages that leave the window are cancelled rather than left to complete, and a request for the Page the reader has actually landed on jumps ahead of prefetches for Pages further down. At most four fetches run at once — the library's Pages average 94 KB, so a fetch costs round-trip latency rather than bandwidth, and four in flight hides that latency without saturating the connection or the decoder.

A failed URL is **marked as failed and not retried automatically**. This is part of this ticket rather than a follow-up because the window reconciler creates the hazard: without the mark it would see "not resident, not in flight", re-request immediately, fail again, and loop — turning a dead network into a request storm. The mark is cleared by an explicit retry or by the reader actually scrolling to that Page; prefetch alone never re-attempts it. The Reader's existing failure placeholder and retry-all behaviour are preserved.

Chapter changes re-seed the window and do **not** clear the cache, so flipping to the previous or next chapter and back stays instant.

The window and progress reporting consume the same "which Pages are visible" signal but must behave oppositely — the window reacts immediately, progress stays debounced, and **prefetching must never cause a progress write**. Keep the two paths visibly distinct rather than sharing a convenience helper that quietly does both; a prefetched Page counted as read is the most damaging failure this feature could introduce.

**Blocked by:** 01 — Page image cache with an instant path for images already in memory.

**Handoff from 01 — read this before starting.** Ticket 01 shipped the cache without any cancellation surface, deliberately. Its fetches run in detached tasks that do **not** inherit cancellation, so a request continues to completion and populates the cache even after the caller goes away. That is correct for 01 — a scrolled-away Page finishing its download is a free cache entry — but it is directly at odds with this ticket's requirement that out-of-window requests be cancelled. Adding a cancellation surface to the cache protocol is part of this ticket's work, not a pre-existing capability to call.

Likewise, 01 has **no failure marking**: a failed fetch simply clears its in-flight entry and a retry genuinely re-requests. That was the right call there, because the retry storm this spec guards against is created by *this* ticket's window reconciler. The marking is yours to add, and it must not break today's tap-to-retry.

**Status:** resolved (commit `667d021`, PR [#60](https://github.com/towfd/vista_comic/pull/60), merged 2026-08-09)

Device-verified by the repo owner before merge, including the two that unit tests can only approximate: scrolling down a chapter at normal speed no longer shows a loading indicator, and reading position is not advanced by Pages fetched ahead of the reader.

- [ ] Scrolling down a chapter on a normal connection shows Pages with no loading indicator
- [ ] Opening a chapter starts fetching immediately, centred on the Page actually being displayed
- [ ] Resuming mid-chapter seeds the window at the resume position, not at the first Page
- [ ] Jumping to a Page from a History record prefetches that Page and the ones after it
- [ ] The window covers the current Page, five ahead and two behind, and slides with the reader
- [ ] A window near the end of a chapter clamps instead of requesting past the last Page
- [ ] Sliding the window forward requests only newly-entered Pages, not ones already resident
- [ ] No more than four fetches are in flight at once
- [ ] Requests for Pages that leave the window are cancelled and stop consuming in-flight capacity
- [ ] A Page the reader has landed on is fetched ahead of prefetches for Pages further down
- [ ] Scrolling quickly through many Pages leaves the landing Page loading promptly, not queued behind Pages already passed
- [ ] A failed URL is not re-requested by a subsequent window reconcile
- [ ] An explicit retry does re-request a previously failed URL, and the existing retry-all placeholder behaviour is unchanged
- [ ] Changing chapters re-seeds the window without clearing the cache; flipping to an adjacent chapter and back is instant
- [ ] Auto-advancing to the next chapter starts prefetching as soon as it opens
- [ ] Prefetching never triggers a progress write, and saved position is unchanged by Pages loaded ahead of the reader
- [ ] Prefetching behaves identically in preview (peek) mode
