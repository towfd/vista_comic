# 01 — Download a chapter to the device

**What to build:** A reader who is about to lose their connection taps download on a chapter, watches it fill, and sees it marked as downloaded. It is still there after the app is closed and relaunched. If they change their mind mid-download they cancel, and the partial chapter is discarded rather than left half-present.

**Nothing reads from the download yet, and that is deliberate.** Making the offline round trip work is ticket 02's whole job; folding it in here would produce a ticket that touches the storage layer, the download engine, the chapter list, the image cache and the repository at once, which is more than one working session can hold. What this ticket delivers on its own is the thing everything else depends on: the bytes, and a record of what they are, genuinely on the device.

This ticket introduces `OfflineChapterStore`, one of the feature's two seams — a protocol injected through the environment like the repositories and the image cache, so tests point it at a temporary directory and previews substitute a double. It owns downloaded *content*: the chapter records, the page bytes, and deletion.

**The chapter record is load-bearing, not bookkeeping.** A chapter's ordered page URLs are otherwise only ever known from a live reader request to the backend, so without a stored record the bytes on disk cannot be reassembled into a readable chapter no matter how many of them there are. Each record holds the comic's id and title, the chapter's id, number and title, the ordered page URLs, the page count, the started-at timestamp, and whether every page arrived.

Downloads live under **Application Support, not Caches**. The system reclaims Caches under disk pressure, which would silently delete the one thing this feature exists to guarantee. The directory is marked excluded from iCloud backup, so a few hundred megabytes of comics never inflate the reader's backup.

The engine runs in the **foreground only**: backgrounding the app pauses it, returning resumes. Resume is **page-level** — a page already on disk is skipped, so an interrupted chapter costs only what had not yet arrived, which matters when a chapter is 60–180 separate requests. Four fetches run at once, matching the image cache's existing in-flight limit and its reasoning: at ~100 KB a page, a fetch costs round-trip latency rather than bandwidth. Requests are built through the same shared authorized-request path as every other backend call, so Cloudflare Access headers are attached exactly as they are everywhere else. A chapter is marked complete only when every page is present.

**A temporary hard stop at 20 chapters is part of this ticket.** It refuses further downloads rather than evicting anything — real first-in-first-out eviction is ticket 04, and it deserves its own ticket because it is the only irreversible, destructive logic in the feature. The stop exists so that the device cannot be filled with several gigabytes in the window between this ticket and that one. Ticket 04 replaces it.

**Blocked by:** None — can start immediately.

**Status:** implemented on branch `feat/offline-download-store`, 2026-08-18 — unit-verified, awaiting the repo owner's device pass (see the checklist at the bottom).

- [x] A chapter row in the chapter list offers a download action and shows its state: not downloaded, downloading with progress, downloaded
- [x] Downloading fetches every page of the chapter and stores it on the device
- [x] A chapter is marked complete only once every page is present
- [x] Downloading can be cancelled, and cancelling deletes the partial chapter
- [x] An interrupted download resumes without re-fetching pages already on disk
- [x] Backgrounding the app pauses the download; returning resumes it
- [x] Downloaded state survives closing and relaunching the app
- [x] At most four page fetches are in flight at once
- [x] Download requests carry the Cloudflare Access headers
- [x] Content is stored under Application Support, not Caches, and is excluded from iCloud backup
- [x] Each downloaded chapter carries a record holding its ordered page URLs, page count, titles, ids, started-at time and completion state
- [x] A download beyond 20 chapters is refused rather than evicting anything
- [x] The store is exercised in tests against an injected temporary directory, never the real Application Support path
- [x] Reading, progress reporting, prefetching and selection are unaffected
- [x] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout

## What was built

- `Networking/OfflineChapterStore.swift` — the `DownloadedChapter` record, the seam, `FileOfflineChapterStore` (one directory per chapter under Application Support, excluded from backup) and an in-memory double used as the environment default and as the launch fallback.
- `Networking/ChapterPageDownloader.swift` — the bytes: four fetches at once through `APIConfig.authorizedRequest`, skipping whatever is already on disk.
- `Networking/ChapterDownloadManager.swift` — the `@Observable` engine: one chapter at a time, queueing, cancel-versus-pause, and the state a row renders.
- `Features/ChapterPage/components/ChapterDownloadButton.swift` + `ChapterListView` — the row affordance, outside the `NavigationLink` so cancelling cannot open the reader.
- `ChapterPageView` presents the at-the-cap refusal; `vista_comicApp` owns the store and the manager and drives pause/resume off `scenePhase`.

**Chapters download one at a time**, which is not an arbitrary policy: four page fetches is the limit, and two chapters at once would be eight. Ticket 06's batch mode plugs into that queue rather than working around it.

## Verification

`BUILD SUCCEEDED`, and the whole `vista_comicTests` target passes, including 19 new tests: 11 in `OfflineChapterStoreTests` (cap, resume-does-not-take-a-second-slot, deletion frees the slot, survives a new store over the same directory, excluded from backup, Application-Support-not-Caches) and 8 in `ChapterDownloadTests` (every page stored, resume fetches only what is missing, at most four in flight, Cloudflare Access headers, a 404 leaves the chapter incomplete and kept, cancelling discards it, pause-and-resume does not re-fetch, refusal at the cap issues no request).

## Device checklist for the repo owner

UI verification is the repo owner's, per `CLAUDE.md`. Run each on **one compact phone and one larger phone**:

1. A chapter row shows the download control; tapping it fills the ring and ends on the downloaded tick.
2. Tap the ring mid-download: it stops, the row returns to not-downloaded, and starting again begins from the beginning.
3. Start a download and background the app; return — it carries on rather than restarting, and finishes.
4. Force-quit after a chapter completes and relaunch: the row still says downloaded.
5. Force-quit *mid*-download and relaunch: the row offers the retry control, and tapping it finishes quickly rather than re-fetching everything.
6. Tap download on several chapters in a row: they queue and complete one after another.
7. With 20 chapters downloaded, tap a twenty-first: the limit alert appears and nothing is evicted.
8. Tapping anywhere on the row other than the control still opens the reader; the control never navigates.
9. Reading, progress, prefetching and selection behave exactly as before on a chapter that was downloaded, and on one that was not.
