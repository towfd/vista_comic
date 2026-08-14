Status: ready-for-agent

# Offline download: chapters you deliberately keep, readable with no network

## Problem Statement

The app cannot be read without a live connection to the backend, and nothing it fetches survives being closed.

`MemoryPageImageCache` says so in as many words: *"Memory only. Nothing is written to disk, and nothing survives launch."* Its 150 MB budget is a reading-distance buffer for the current session, not storage. Relaunching the app empties it.

The metadata situation is what actually makes offline reading impossible, and it is easy to miss. Even if the bytes of twenty chapters were sitting on the device, none of them could be reached:

- `FavouriteView` calls `library()` → `GET /comics`. On failure the whole screen becomes an `ErrorStateView`.
- `ComicView` calls `comic(id:)` → `GET /comics/{id}` to resolve the chapter list before the Reader can exist at all.
- `ReaderView.loadPages()` calls `readerChapter(comicID:chapterID:)` → `GET /comics/{id}/chapters/{cid}`, and **that response is the only source of the ordered page URLs**. Without it the Reader has no list of pages to show, cached or otherwise.

So a reader on a plane, on a train, or anywhere the personal tunnel is unreachable gets an error page and nothing else. With the library now past 300 chapters, the situations where the content is wanted and the network is not there are ordinary rather than exotic.

## Solution

A reader can **download a chapter** and read it later with no connection at all.

Downloading is a deliberate act, and the disk holds only what was deliberately downloaded. Pages that merely passed through the Reader are not kept — that keeps three things exactly aligned that would otherwise drift apart: what the download list shows, what counts against the limit, and what is actually on disk. There are no chapters that happen to work offline.

**The cap is 20 chapters, counted across the whole library.** When a download would exceed it, the oldest download is removed automatically, first-in-first-out by when it was started, and the new one proceeds. The reader is not stopped and asked to tidy up.

**Both offline surfaces are built.** The library keeps working without a connection by falling back to the last successful catalog responses, so browsing, covers, chapter lists and the download markers are all still there. Separately, a **已下載** screen lists every downloaded chapter for review, deletion, and as the direct entry point to offline reading.

**The Reader itself is not modified.** A disk store is inserted inside the image cache, between memory and network: memory hit → disk hit → network. A downloaded page therefore loads from disk even when the connection is fine, which is faster and cheaper, and the Reader never learns which source answered. What the Reader does gain, indirectly, is a page list that survives: each downloaded chapter carries its own record of the ordered page URLs, so `readerChapter` can be answered locally when the network cannot answer it.

**Reading progress is no longer discarded when it cannot be sent.** `sendProgress` currently swallows failures, which was correct when a failure meant a blip. Once reading offline is normal, that silently loses a whole session — land, reconnect, and the app believes nothing was read. Progress that cannot be written is queued locally, one entry per chapter, and flushed on the next successful request.

No backend, API contract, or schema change is required.

## User Stories

1. As a reader, I want to download a chapter for offline reading, so that I can read it where there is no connection.
2. As a reader, I want to select several chapters at once and download them together, so that preparing for a trip is not one tap per chapter.
3. As a reader, I want to see at a glance which chapters are downloaded, so that I know what I can rely on.
4. As a reader, I want to see a chapter's download progress while it runs, so that I know whether it finished.
5. As a reader, I want to cancel a download in progress, so that I am not stuck waiting for something I no longer want.
6. As a reader, I want a download that was interrupted to resume rather than start over, so that a bad connection does not waste what already succeeded.
7. As a reader, I want to know that a partially downloaded chapter is not yet readable offline, so that I do not discover it mid-flight.
8. As a reader, I want downloads to be capped, so that the app cannot quietly fill my phone.
9. As a reader, I want to know how much of the cap I have used, so that the limit is not a surprise.
10. As a reader who hits the cap, I want the oldest download removed automatically, so that downloading never becomes a chore of manual cleanup.
11. As a reader, I want to browse my library without a connection, so that the app is usable rather than an error page.
12. As a reader, I want covers and chapter lists to still be there offline, so that the library looks like itself.
13. As a reader, I want to open and read a downloaded chapter with no connection, so that the feature does what it claims.
14. As a reader offline, I want a chapter I did not download to say so clearly, so that I am not left staring at a generic failure.
15. As a reader, I want a dedicated list of everything I have downloaded, so that I can review and manage it in one place.
16. As a reader, I want to delete a downloaded chapter, so that I can free a slot for something I would rather have.
17. As a reader, I want to delete everything downloaded at once, so that reclaiming space is one action.
18. As a reader, I want my page position saved while reading offline, so that resuming works the same as it does online.
19. As a reader, I want offline progress sent to the server once I reconnect, so that my history and "continue reading" are correct afterwards.
20. As a reader, I want a downloaded chapter to load instantly even when I am online, so that downloading also makes reading better.
21. As a reader, I want downloading not to make the app unresponsive, so that I can keep reading while a download runs.
22. As a reader, I want downloads not to be counted in my iCloud backup, so that offline chapters do not bloat it.
23. As a reader, I want downloaded content to survive relaunching the app, so that "downloaded" means what it says.
24. As a reader, I want selection, recognition and translation to work normally on a downloaded page, so that offline reading is the same experience minus the network.
25. As a reader behind Cloudflare Access, I want downloads authenticated like every other request, so that they do not fail at the edge.
26. As a developer, I want the cap, eviction and resume rules testable without a network or a view, so that the destructive parts can be verified quickly.

## Implementation Decisions

### The seams

**Two new seams, and no more.** Both are protocols injected through the SwiftUI environment, following the pattern already established for the repositories, the recognizer, the translator and the image cache, so previews and tests substitute their own.

- **`OfflineChapterStore`** — everything about downloaded *content*: chapter records, page bytes on disk, the used-of-cap count, admitting a download (which is what triggers eviction), and deletion. Its live implementation owns a directory; tests point it at a temporary one or substitute an in-memory double.
- **`PendingProgressStore`** — reading positions that could not be sent: enqueue, read back, drop on successful flush. Kept separate from the content store deliberately, because the two have different lifetimes — downloaded content is evicted by the cap, a queued position disappears only when the server has accepted it, and neither event should be able to touch the other.

Everything else reuses an **existing** seam rather than adding one:

- **`PageImageCache` is unchanged as a protocol.** Its live implementation gains a dependency on `OfflineChapterStore` and consults it before the network. No call site changes, and the Reader has no offline code path at all.
- **`ComicRepository` is unchanged as a protocol.** A decorator implementation wraps the live API repository and adds catalog caching, offline fallback, and progress queueing. Every screen keeps depending on exactly what it depends on today.
- **The download engine is a concrete observable type, not a protocol.** It depends only on `OfflineChapterStore`, so a test or preview drives its observable state by substituting that store — a third seam would buy nothing the second one does not already give.

### What is stored, and where

Downloads live under **Application Support**, not Caches — the system reclaims Caches under disk pressure, which would silently delete the one thing the feature promises to keep. The directory is marked excluded from iCloud backup.

Per downloaded chapter:

- The page image files, named from the page URL so the disk store is keyed the same way the memory cache is.
- A **chapter record** holding everything needed to read and to display the chapter with no network: comic id and title, chapter id, number and title, the ordered page URLs, page count, the started-at timestamp (the FIFO key), and a completed flag.

The chapter record is the load-bearing piece. `Chapter.pageURLs` is otherwise only ever known from a live `GET /comics/{id}/chapters/{cid}`, so without the record the bytes on disk cannot be assembled into a chapter.

### The disk layer sits inside the image cache

The image cache currently resolves a URL through a single fetch path — fetch over the network, force the decode, store in memory. That path gains one step in front: **ask the disk store first**, and only fall through to the network on a miss. Everything downstream — the prefetch window, concurrency limits, failure marking, forced decoding, the synchronous memory hit path — is unchanged, and `AuthorizedAsyncImage` and the Reader are untouched.

Two properties follow for free: a downloaded page is fast even when online, and the Reader has no offline code path to get wrong.

Writing is deliberately **not** symmetric. Only the download engine writes to disk; the read path never populates it. That is what keeps the disk contents equal to the download list.

### Catalog fallback for offline browsing

`APIComicRepository` stores the **raw response bytes** of successful `GET /comics` and `GET /comics/{id}` calls, and on a network failure decodes the stored bytes instead of throwing. Raw bytes rather than re-encoded models, because `Comic` and `Chapter` are `Decodable` only — this needs no `Encodable` conformance, no second representation, and no model change of any kind.

`readerChapter(comicID:chapterID:)` falls back differently: on failure it looks for a **completed** chapter record and answers from it, with the resume position taken from the local progress queue when one is pending. A chapter that was never downloaded, or is only partly downloaded, fails as it does today — but the Reader distinguishes that case and shows "this chapter is not available offline" rather than the generic connection error.

### The cap and eviction

- The limit is **20 chapters, global**, held as a single constant. There is no settings screen and none is added.
- A download **occupies its slot from the moment it starts**, so queuing many at once cannot exceed the cap.
- When a new download would exceed the cap, the **oldest by started-at** is deleted — record and files together — and the new one proceeds. Strict FIFO; read state is not consulted.
- Eviction is applied per chapter admitted, so a batch of five is exactly five evictions.
- The chapter currently open in the Reader is never evicted while it is open.

The failure mode this accepts, recorded because it was raised and knowingly accepted: a chapter saved for a trip can be evicted by later downloads before it is read. The 已下載 list makes the queue visible so it can be seen coming.

### The download engine

- **Foreground only.** Backgrounding the app pauses; returning resumes.
- **Page-level resume.** A page already on disk is skipped, so an interrupted chapter costs only what it had not yet fetched.
- Four concurrent fetches, matching the image cache's existing in-flight limit and its reasoning — page fetches cost round-trip latency, not bandwidth.
- Requests are built through `APIConfig.authorizedRequest`, so Cloudflare Access headers are attached exactly as everywhere else.
- Progress is reported as completed pages over total pages; a chapter is marked complete only when every page is present.
- Cancelling stops the work and deletes the partial chapter.
- No network-type restriction and no Wi-Fi-only setting.

### Offline progress queue

Owned by `PendingProgressStore`; the repository decorator is its only caller.

- Keyed by (comic id, chapter id), holding only the most recent page for that chapter — last write wins, so a whole offline session collapses to one entry per chapter rather than a log.
- Bounded, and persisted so it survives relaunch.
- Flushed after the next successful backend request; entries that flush successfully are dropped.
- `sendProgress`'s existing contract is preserved: it still never interrupts reading and never surfaces an error. It now enqueues instead of discarding.

This is a queue, not a sync engine. The backend stays the source of truth for progress; there is no merge policy and no conflict resolution.

### User interface

- **Chapter list**: each row gains a state affordance — not downloaded, downloading (with progress), downloaded — plus a multi-select batch mode for downloading several chapters in one action.
- **已下載 screen**: every downloaded chapter grouped by comic, with its size and state, per-chapter delete, delete-all, and the used-of-cap count. It opens the Reader directly, which is the offline entry point.
- Offline, the library renders from the cached catalog. Chapters that are not downloaded remain visible and tappable, and produce the explicit not-available-offline message.

## Testing Decisions

Assert on observable behaviour — what is on disk, which URLs were requested, what the repository returns — never on internal container shapes. `APIComicRepositoryTests`' file-private `URLProtocol` stub over an ephemeral session is the right prior art, extended to fail on demand so the offline fallbacks can be driven. Disk tests run against a temporary directory injected into the store, never the real Application Support path.

The two new seams carry most of the weight, and the third and fourth groups below need no network at all:

- **`OfflineChapterStore`** is exercised directly against a temporary directory — this is where the cap, eviction and deletion are proven.
- **The repository decorator** is exercised with a hand-written inner `ComicRepository` double that throws on demand, plus a substituted `PendingProgressStore`. No `URLProtocol` stub is needed to test a fallback, because the failure is injected one level higher.
- **The image path** is exercised with a substituted `OfflineChapterStore` plus the `URLProtocol` stub, asserting the network was not reached. Prior art: `PageImageCacheTests`.

- Downloading a chapter writes every page, and the chapter reports complete.
- Re-running an interrupted download requests only the missing pages.
- Cancelling deletes the partial chapter and frees its slot.
- A partially downloaded chapter never reports as available offline.
- Admitting a download at the cap evicts exactly the oldest by started-at, and the count returns to the cap rather than exceeding it.
- A batch admitting five at the cap evicts exactly five.
- Deleting a chapter removes both its files and its record, and frees a slot.
- The image path resolves a downloaded URL from disk with no network request issued.
- A non-downloaded URL still goes to the network exactly as before.
- Reading a page does **not** write it to disk.
- `library()` and `comic(id:)` return the cached catalog when the network fails, and the live response when it succeeds.
- `readerChapter` returns the recorded page list for a completed download when the network fails, and throws a distinguishable not-available-offline error for one that was never downloaded.
- Progress that fails to send is queued; a second write for the same chapter replaces the first rather than appending; the queue flushes and empties after a successful request.
- Downloads carry the Cloudflare Access headers.

**No XCUITest is written for this feature**, per `CLAUDE.md`'s verification rules. The on-device checklist to hand off: download two chapters and confirm the markers; enable airplane mode and confirm the library still renders, a downloaded chapter reads end to end, and a non-downloaded one gives the explicit message; read several pages offline, reconnect, and confirm the position and read state catch up; interrupt a download by backgrounding and confirm it resumes; drive past the cap and confirm the oldest disappears; delete a chapter and confirm the space is freed; confirm on one compact-phone and one larger-phone layout.

## Out of Scope

- **Background downloading.** Considered: 60–180 tasks per chapter through a background `URLSession`, with delegate-driven re-association after app termination, is comparable in size to the rest of this feature. Revisit only if pausing on backgrounding proves to be the actual complaint.
- **A Wi-Fi-only toggle, and any user-configurable cap.** Both imply a settings surface the app does not have.
- **Opportunistic disk caching of pages merely read.** Explicitly rejected: it would decouple what is on disk from what the reader chose to keep, and make the cap meaningless.
- **Two-way progress sync, conflict resolution, or a local-first progress store.** The queue is one-directional catch-up.
- **Downloading a whole comic in one action.** The batch selector covers the real need at a 300+ chapter scale.
- **Offline support for 歷史紀錄, comprehension, OCR requests to the backend, or `rescan()`.** Selection and on-device translation continue to work on a downloaded page; anything that needs the cloud fails as it does today.
- **Backend changes** — no `Cache-Control` headers, no archive endpoint, no page-dimension fields.
- **Any change to the Reader's scrolling, progress, prefetch, or selection behaviour.**

## Further Notes

Measured on the library the backend was configured against at the time of writing — 2 comics / 16 chapters / 1757 pages / 175 MB; the repo owner reports the working library has since grown past 300 chapters. Per-chapter shape should be unchanged, since it is the same source and format:

- A page is ~100 KB at 900px wide.
- A chapter is **5–20 MB across 60–180 files** — a fourfold spread, which is why the cap is chapters rather than bytes and why the disk figure is a range.
- 20 chapters is therefore roughly **100–400 MB**.
- At 300+ chapters the cap binds in ordinary use, so FIFO eviction will be exercised on a real device rather than only in tests.

Three things to watch during implementation. **Eviction is destructive and irreversible** — it is the highest-risk code here, and its tests are the ones that matter most. **The disk-write boundary is the invariant that holds the design together**: the moment the read path starts writing, the cap, the list and the disk stop agreeing, and every user-facing statement about what is available offline becomes untrue. And **the offline catalog fallback must not mask a live failure** — a real server error should still surface as an error rather than silently serving a stale catalog that looks fine and is quietly out of date.

This feature and `.scratch/reader-zoom/` are independent. They meet only at the image cache, where the disk layer sits below everything the Reader sees.
