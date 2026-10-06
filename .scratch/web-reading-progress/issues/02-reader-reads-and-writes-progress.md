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

**Status:** done 2026-10-06 — resume, gate, debounce/flush and the PUT are in; merged in #104 and browser-verified by the developer.

- [x] `client.ts` gains `saveProgress(comicId, chapterId, lastPage, { keepalive? })` — `PUT` with JSON `{ lastPage }`, the same `redirect: 'manual'` and error shaping as `getJson`; unit-tested (body, method, encoded ids, auth redirect → `auth`, 503 → `unavailable`)
- [x] `types.ts`: `lastReadPage` no longer documented as ignored
- [x] The PUT is confirmed through the Vite proxy against the real backend once (status and echoed body recorded below), then the test row's progress is put back to what it was
- [x] Resume: lands on `lastReadPage`, clamped; unit tests cover none / in range / above `pageCount` / below 1 / finished chapter / top override
- [x] Reader refetches the chapter on every open; no stale resume after reading and reopening
- [x] Reserved box is 900:1549 for loading and error states
- [x] Current page from `IntersectionObserver`; unit tests cover top-most visible, end visible → `pageCount`, nothing visible → none
- [x] Gate: open-and-leave writes nothing; unit test for the write decision (gate closed / unchanged page / changed page)
- [x] Debounce ~1 s; flush on route leave and on tab hidden with `keepalive`
- [x] Failed save → `console.warn` only, reading uninterrupted
- [x] `vue-tsc` clean, vitest green

## What was built

- `src/reader/progress.ts` — the pure rules, no DOM: `resumeStartPage({ pageCount, lastReadPage, startAtTop })` (1-based page, or `null` = top; clamped; finished → last page; `startAtTop` wins), `currentPage(visible, endVisible, pageCount)` (top-most visible; end visible → `pageCount`; nothing → `null`), `shouldWrite({ gateOpen, page, lastSent })`, `isScrollKey(key)`.
- `src/reader/progressSaver.ts` — `createProgressSaver(save, delayMs = 1000)`, one per opened chapter: `update(page)`, `openGate()`, `flush({ keepalive })`, `dispose()`. Holds the gate, the debounce (reads the latest page when it fires), and `lastSent`. A failed save resets `lastSent`, so the next debounce/flush is the natural retry. No network code; `save` is injected.
- `src/api/client.ts` — `saveProgress(comicId, chapterId, lastPage, { keepalive? }, fetcher?)`: `PUT` JSON `{ lastPage }`. `getJson` and it now share one private `requestJson`, so redirect/401/403/HTML → `auth`, 5xx → `unavailable`, 404 → `notFound`, 422 → `unexpected` are the same for both. `types.ts` gains `ProgressSaved` and documents `lastReadPage` as the resume position.
- `src/stores/chapters.ts`:
  - `load` always refetches and drops the cached copy first (the reader shows 「載入中」), discards a late, superseded response, and **awaits in-flight saves before fetching**, so reopening a chapter just left resumes at the flushed page.
  - `saveProgress(...)` → `Promise<boolean>`, never rejects; a failure is one `console.warn`.
  - **`savesSettled(): Promise<void>` is the observable in-flight save for ticket 04**: it resolves once every save sent so far has been answered. Ticket 04's comics-store revalidation does `await useChaptersStore().savesSettled()` before `fetchComic`.
- `src/views/ReaderView.vue` — wires DOM facts into the above:
  - each page sits in a stable `[data-page]` wrapper (the `<img>`/error box inside swaps elements; the wrapper does not). One `IntersectionObserver` watches those wrappers and the 「本話完」 block (`endEl`).
  - After the fresh chapter renders (`watch(..., { flush: 'post' })`) it scrolls the start page into view (`behavior: 'instant'`) or to the top, *then* marks `positioned` and starts observing.
  - `wheel` / `touchmove` (passive) / `keydown` ↓ PageDown Space on `window` open the gate only once `positioned`.
  - `visibilitychange → hidden` → flush with `keepalive`; `onBeforeRouteLeave` → flush; a param change (same component reused) flushes the old chapter's saver before creating the new one.
  - **`flushProgress()` is the flush ticket 03's button calls** before `router.replace`; a second flush from the param change is a no-op (same page as last sent).
  - **`takeStartAtTop()` is the override hook for ticket 03**: it returns `false` today; ticket 03 makes it read and clear the `history.state` flag. `resumeStartPage` already takes `startAtTop`.
- `src/components/ReaderPage.vue` — loading and error boxes reserve `aspect-[900/1549]`.

## Verification done

- `npm run typecheck` (vue-tsc) clean; `npm run build` OK; `npm test` 52/52 across 4 files (33 new):
  - `reader/progress.test.ts`: resume (none / in range / above / below 1 / finished / top override / empty), current page (top-most / end → `pageCount` / nothing → none / empty chapter), write decision (gate closed / unchanged / changed / no page), keys.
  - `reader/progressSaver.test.ts` (fake timers): open-and-leave sends nothing, ~1 s debounce sends the latest once, flush sends immediately with `keepalive` and cancels the debounce, no resend of the same page, a failed save is retried by the next flush, dispose cancels.
  - `api/client.test.ts`: `saveProgress` method/body/`redirect: 'manual'`/content type, encoded ids, keepalive passthrough, 302 → `auth`, 503 → `unavailable`, 422 → `unexpected`.
  - `stores/chapters.test.ts`: refetch on every load with the cache dropped meanwhile, load waits for an in-flight save, `savesSettled` resolves only when the save does, a failed save → one `console.warn`, resolves `false`.
- **The PUT through the Vite proxy against production** (`localhost:5173`, a dev server already running from `web/`): Frieren ch 88 (`63d82d8f2f73a6d3` / `47fa6a93846638fa`) had `lastReadPage` 3. `PUT {"lastPage": 3}` → **HTTP 200**, echo `{"comicId":"63d82d8f2f73a6d3","chapterId":"47fa6a93846638fa","lastPage":3,"pageCount":22,"updatedAt":"2026-10-06T14:52:09.038316+00:00"}`. GET afterwards: still 3.
  - Side effect, then repaired: the newer `updatedAt` moved Frieren's `continueChapterId` from ch 87 (`2a41888fddb9aa4f`) to ch 88, because Continue picks the most recently updated `reading` chapter. Sending ch 87 its own unchanged `lastReadPage` 5 → 200, which restored `continueChapterId` to ch 87. What remains changed: those two rows' `updatedAt`, so Frieren's `lastReadAt` now reads 2026-10-06.
- Not exercised here: the browser behaviour (the checklist below belongs to the developer).

## Browser checklist for the developer

- [x] A chapter with phone progress opens on that page and stays there while nearby pages load
- [x] Open a chapter, don't scroll, go back → no `PUT` in the network panel
- [x] Trackpad-scroll and stop → one `PUT` about a second later, with the top-most visible page
- [x] Reach 「本話完」 → `PUT` with `lastPage == pageCount`
- [x] Back link, and switching tab away → a `PUT` fires immediately
- [x] Reopen the same chapter → it resumes at the page just read, not the earlier one
- [x] The phone shows the web's position, and vice versa
- [x] Every request goes to `localhost:5173`
