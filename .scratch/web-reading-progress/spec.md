Status: ticketed (2026-10-06)

# Web reading progress: resume where you left off, on either device

## Problem Statement

The web reader (`.scratch/web-reader-mvp/`) shows the library, a chapter list and a continuous reader, but it neither reads nor writes reading progress. Every chapter opens at the top, nothing read on the computer reaches the phone, and finding where you were in a 1162-chapter comic means scrolling the list by eye.

The MVP cut progress deliberately: writing it needs a rule for what counts as read while scrolling, and the iOS reader already has a defect report about exactly that judgement (`.scratch/reader-auto-advance-false-trigger/`). This spec settles that rule for the web.

## Solution

The web reader shares the **one** progress store the backend already has — the same rows the iOS app reads and writes. No per-device progress.

- **Read**: opening a chapter positions the reader at its `lastReadPage`.
- **Write**: while reading, the web reports the current page with the same rule iOS uses, through the existing `PUT /comics/{comicId}/chapters/{chapterId}/progress`.
- **Continue**: the chapter list gets a 「繼續閱讀 · 第 N 話」 button that opens the chapter the backend picks for Continue.
- **Next chapter**: the end of a chapter gets a 「下一話 · 第 N 話」 button that opens the following chapter from its top.

Everything except the Continue button uses endpoints that already exist. The button needs one small backend addition: `continueChapterId` on `GET /comics/{comicId}`.

## User Stories

1. As the reader, I want a chapter to open where I left it — on the computer or on the phone — so that I never hunt for my place.
2. As the reader, I want what I read on the computer to show on the phone (read badges, Continue, resume position), and the other way round, so that the two devices feel like one library.
3. As the reader, I want a chapter-list button that takes me straight to the chapter I'm on, so that I don't scroll a thousand-chapter list to find it.
4. As the reader, I want merely opening a chapter to leave my saved position untouched, so that peeking at a chapter can't throw away where I was on the phone.
5. As the reader, I want the page I resumed at to stay put while the pages around it load, so that resuming lands me where it says.
6. As the reader, I want a button at the end of a chapter that takes me to the next one, so that reading several chapters in a row doesn't mean a trip through the chapter list each time.
7. As the reader, I want progress saving never to interrupt reading, so that a backend hiccup costs at most a little position, never an error on screen.

## Implementation Decisions

### One shared store

Progress is written to and read from the backend's existing table, keyed by `(comic_id, chapter_id)` with no device column. A wrong write from the web therefore corrupts the phone's progress too — which is why the write gate below is the centre of this spec.

### Reading: resume on open

- On open, the reader scrolls to page `lastReadPage` (1-based), **clamped** to `[1, pageCount]` in case the chapter shrank. No `lastReadPage` → start at the top.
- **A finished chapter (`lastReadPage == pageCount`) opens on its last page, the same as iOS** (`readerStartIndex` in `ComicView.swift`). Re-reading it from the top lowers it from `read` back to `reading`, also the same as iOS. Known consequence, accepted: when every chapter is read, Continue opens chapter 1 — on its last page.
- **The reader always refetches `GET chapter` when it opens**, and shows 「載入中」 until it arrives rather than rendering a cached copy. The chapters store caches forever today; a cached `lastReadPage` would resume at a stale page, and jumping to a stale page then jumping again is worse than a short wait.

### Keeping the resumed page still

Pages not yet loaded reserve `aspect-[2/3]` today: 1200px in the 800px column, against roughly 1377px for a real 900×1549 page. `loading="lazy"` fetches pages a screen or two above the resume point, and each one that arrives pushes the page being read down by ~177px.

- **Reserve the measured ratio, 900:1549**, instead of 2:3 — the same `defaultPageHeightRatio` iOS uses, measured across the library in 2026-08.
- **Rely on Chrome's scroll anchoring** for the residual. No JavaScript compensation. The developer reads in Chrome; Safari, which lacks full scroll anchoring, is out of scope.

### Writing: the current page — the same rule as iOS

- **Current page = the top-most page with any part visible** (iOS `reportedProgressPage`: `visiblePages.min() + 1`).
- **When the 「本話完」 block enters the viewport, the current page is `pageCount`** — that is what marks a chapter `read`.
- Visibility comes from `IntersectionObserver` on each page and on the end block, **not** from scroll offsets and content height. Inferring position from scroll geometry is exactly what produced the iOS defect.

### Writing: the gate — nothing is written until the reader really scrolls

On open the column is briefly at the top with page 1 visible, before the resume scroll; and images loading above the viewport can move the top-most visible page without the reader doing anything. Either would write a wrong page over the phone's position.

- **No progress write happens until a real user input is seen** after the chapter has been positioned: `wheel` (which covers trackpad scrolling, the developer's main input), touch dragging, or the keys ↓, PageDown and Space. Open-and-look writes nothing.
- Known gap, accepted: dragging the scrollbar thumb raises no event that can be told apart reliably, so a scrollbar-only scroll does not open the gate until the next wheel/touch/key input.

### Writing: when a save is sent

- **Debounced**: about one second after the current page stops changing (iOS uses 0.9 s).
- **Flushed immediately** — cancelling any pending debounce — when:
  - the reader route is left inside the app (the back link, browser back);
  - the tab becomes hidden (`visibilitychange` → `hidden`), which in Chrome also covers closing the tab and reloading. This request uses `fetch` with `keepalive: true` so it survives the page going away.
- **Not sent if the page equals the last one sent.**
- Scrolling in the last second before a tab closes without any of these firing can be lost — the same tolerance as iOS.

### Writing: failures

- **Silent.** A failed save logs one `console.warn` and nothing else: no retry, no UI. The next debounce or flush sends the latest position anyway, which is a natural retry. An Access token failure already shows as every image failing.
- Unlike iOS, there is **no offline queue**. A progress-store outage that lasts until the tab closes loses that stretch of progress. Accepted.

### The PUT through the proxy

`PUT /comics/.../progress` sits under the already-proxied `/comics` prefix, so the Vite proxy should forward it with the Service Token unchanged. **Confirmed with a real request during implementation**, not assumed.

### Chapter list freshness

- **Stale-while-revalidate**: on every visit the chapter list renders its cached copy at once and refetches `GET /comics/{comicId}` in the background, so read badges and Continue catch up without the list flashing.
- **That refetch waits for any in-flight progress save from the reader** — the flush sent while leaving it — so the refreshed badges include what was just read.
- **The library is unchanged**: it shows no progress, so it keeps loading once.

### Continue button

- At the top of the chapter list, under the title and above the chapters, in primary-button style: **「繼續閱讀 · 第 N 話」**, where N is the `number` of the chapter whose id is `continueChapterId`. It opens the reader on that chapter, which resumes at its `lastReadPage` like any other open.
- **Always shown**, as on iOS — with no progress it points at chapter 1. One label, no separate 「開始閱讀」.
- **Hidden when the response has no `continueChapterId`** (backend not yet deployed, or the id is not in the list). The web change can merge before the backend deploys.

### Next-chapter button

- **Below 「本話完」, in primary-button style: 「下一話 · 第 N 話」**, matching the Continue label. The existing 「回到章節列表」 link stays beneath it.
- **Which chapter is next comes from the comic's chapter list**, not from the chapter endpoint (`ChapterDetail` carries no neighbour). The reader uses the comics store's cached `GET /comics/{comicId}` if present, otherwise fetches it in the background — it never blocks the pages. Next = the entry after the current chapter id in that list's order.
- **Hidden on the last chapter**, and hidden until the chapter list has arrived.
- **The next chapter opens at its top, ignoring its `lastReadPage`** — the same as iOS auto-advance (`readerStartIndex`'s `restart` branch). The gate still applies, so the next chapter's saved position is untouched until the reader scrolls.
  - The "start at the top" flag travels in `history.state`, not the URL, and is **cleared once applied**, so reloading mid-chapter resumes from the saved position instead of restarting.
- **Navigation uses `router.replace`**: after reading chapters 5 → 6 → 7, browser back returns to the chapter list, not through 6 and 5.
- **Pressing it flushes progress** like any leave. With 「本話完」 visible that sends `pageCount`, marking the finished chapter `read`.

### Backend: `continueChapterId` on `GET /comics/{comicId}`

- `ComicDetail` gains `continueChapterId: str`, computed in `get_comic` with the existing `progress_store.continue_chapter_id(comic.chapters, rows)` from the `rows` it already queries. One source of the rule, no extra query. With the progress store down, `rows` is `{}` and it degrades to the first chapter, as the list endpoint does.
- `docs/api-contract.md` documents the new field.
- iOS is unaffected: `Codable` ignores keys it does not know.
- **Deploying the backend is the developer's step.** The web reaches production `api.vistabanana.com` through the proxy, so the button appears only after that deploy.

## Testing Decisions

- **Web unit tests (vitest)** for the pure logic, kept out of components so it can be tested without a DOM:
  - current page from the visible set and the end block (top-most visible; end visible → `pageCount`; nothing visible → no page);
  - resume start page (no `lastReadPage` → top; clamping above `pageCount` and below 1; a finished chapter → last page);
  - the write decision (gate closed → no write; unchanged page → no write);
  - the next chapter from a chapter list and the current id (middle → following entry; last → none; id not in list → none);
  - the API client's progress `PUT` and its error shaping, and decoding `continueChapterId` (present and absent).
- **Backend (pytest)**: `GET /comics/{comicId}` returns `continueChapterId` matching the list endpoint's choice, including with no progress rows.
- **The proxy forwarding the PUT** is confirmed once against the real backend.
- **Browser verification belongs to the developer**, per `CLAUDE.md`. The deliverable is a checklist, at minimum:
  - Open a chapter with phone progress → it lands on that page and stays there while nearby pages load.
  - Open a chapter and don't scroll, then go back → no `PUT` in the network panel; the phone still shows its old position.
  - Scroll with the trackpad, stop → one `PUT` about a second later with the top-most visible page.
  - Reach 「本話完」 → `PUT` with `lastPage == pageCount`; back in the chapter list the badge reads 已讀.
  - Leave via the back link and via a hidden tab → a `PUT` fires immediately each time.
  - Continue button names the right chapter and opens it at its resume page; after reading another chapter and returning, it has updated.
  - At the end of a chapter, 「下一話」 names the right chapter and opens it at its top, even when that chapter has a saved position; the last chapter shows no button; browser back after two next-chapter hops lands on the chapter list.
  - Read on the web, then open the phone → same position and badges, and the reverse.
  - Every request still goes to `localhost:5173`.

## Out of Scope

- **Continue on the library screen**, and any other library change.
- **An offline / retry queue** for failed saves.
- **Safari and other browsers without scroll anchoring**, and JS scroll compensation.
- **The page number in the URL** or deep-linking to a page.
- **A rule that `read` never goes back to `reading`** — re-reading lowers it, as on iOS.
- **Auto-advance** (pulling past the end to open the next chapter) and a previous-chapter button.
- **Any change to the iOS app.**
