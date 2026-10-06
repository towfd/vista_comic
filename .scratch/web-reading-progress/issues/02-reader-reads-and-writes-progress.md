# 02 — The reader resumes and saves progress

**What to build:** Opening a chapter lands on its `lastReadPage`; reading reports the current page back through `PUT /comics/{comicId}/chapters/{chapterId}/progress`, into the same store the phone uses. Every rule is in the spec's "Reading" and "Writing" sections; the short version:

- **Resume** at `lastReadPage`, clamped to `[1, pageCount]`; none → top; a finished chapter opens on its last page (as iOS).
- **The reader always refetches `GET chapter` on open** and shows 「載入中」 until it arrives — no cached `lastReadPage`.
- **Reserve 900:1549** for unloaded pages instead of 2:3 (in `ReaderPage.vue`'s loading box and error box); rely on Chrome scroll anchoring for the rest.
- **Current page** = top-most page with any part visible; 「本話完」 visible → `pageCount`. From `IntersectionObserver`, never from scroll offsets.
- **Gate**: nothing is written until a real input after positioning — `wheel`, touch drag, or ↓ / PageDown / Space.
- **Send**: ~1 s debounce; flush immediately on route leave and on `visibilitychange → hidden` (`keepalive: true`); skip if equal to the last page sent.
- **Failure**: one `console.warn`, nothing else.

**Shape for ticket 03 and 04 to build on:**
- The pure decisions — current page from visibility, resume start page, whether to write — live outside the component (e.g. `src/reader/progress.ts`) so they are vitest-testable without a DOM.
- The flush is callable by the reader (ticket 03's next-chapter button calls it) and the in-flight save is observable as a promise somewhere a store can await it (ticket 04's chapter-list refetch waits on it). Where that promise lives is this ticket's call; record it under "What was built".
- Resume must accept a "start at the top" override (ticket 03 sets it); this ticket only needs the parameter, not the caller.

**Blocked by:** none

**Status:** ready

- [ ] `client.ts` gains `saveProgress(comicId, chapterId, lastPage, { keepalive? })` — `PUT` with JSON `{ lastPage }`, the same `redirect: 'manual'` and error shaping as `getJson`; unit-tested (body, method, encoded ids, auth redirect → `auth`, 503 → `unavailable`)
- [ ] `types.ts`: `lastReadPage` no longer documented as ignored
- [ ] The PUT is confirmed through the Vite proxy against the real backend once (status and echoed body recorded below), then the test row's progress is put back to what it was
- [ ] Resume: lands on `lastReadPage`, clamped; unit tests cover none / in range / above `pageCount` / below 1 / finished chapter / top override
- [ ] Reader refetches the chapter on every open; no stale resume after reading and reopening
- [ ] Reserved box is 900:1549 for loading and error states
- [ ] Current page from `IntersectionObserver`; unit tests cover top-most visible, end visible → `pageCount`, nothing visible → none
- [ ] Gate: open-and-leave writes nothing; unit test for the write decision (gate closed / unchanged page / changed page)
- [ ] Debounce ~1 s; flush on route leave and on tab hidden with `keepalive`
- [ ] Failed save → `console.warn` only, reading uninterrupted
- [ ] `vue-tsc` clean, vitest green

## Browser checklist for the developer

- [ ] A chapter with phone progress opens on that page and stays there while nearby pages load
- [ ] Open a chapter, don't scroll, go back → no `PUT` in the network panel
- [ ] Trackpad-scroll and stop → one `PUT` about a second later, with the top-most visible page
- [ ] Reach 「本話完」 → `PUT` with `lastPage == pageCount`
- [ ] Back link, and switching tab away → a `PUT` fires immediately
- [ ] Reopen the same chapter → it resumes at the page just read, not the earlier one
- [ ] The phone shows the web's position, and vice versa
- [ ] Every request goes to `localhost:5173`
