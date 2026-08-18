# 01 — Download a chapter to the device

**What to build:** A reader who is about to lose their connection taps download on a chapter, watches it fill, and sees it marked as downloaded. It is still there after the app is closed and relaunched. If they change their mind mid-download they cancel, and the partial chapter is discarded rather than left half-present.

**Nothing reads from the download yet, and that is deliberate.** Making the offline round trip work is ticket 02's whole job; folding it in here would produce a ticket that touches the storage layer, the download engine, the chapter list, the image cache and the repository at once, which is more than one working session can hold. What this ticket delivers on its own is the thing everything else depends on: the bytes, and a record of what they are, genuinely on the device.

This ticket introduces `OfflineChapterStore`, one of the feature's two seams — a protocol injected through the environment like the repositories and the image cache, so tests point it at a temporary directory and previews substitute a double. It owns downloaded *content*: the chapter records, the page bytes, and deletion.

**The chapter record is load-bearing, not bookkeeping.** A chapter's ordered page URLs are otherwise only ever known from a live reader request to the backend, so without a stored record the bytes on disk cannot be reassembled into a readable chapter no matter how many of them there are. Each record holds the comic's id and title, the chapter's id, number and title, the ordered page URLs, the page count, the started-at timestamp, and whether every page arrived.

Downloads live under **Application Support, not Caches**. The system reclaims Caches under disk pressure, which would silently delete the one thing this feature exists to guarantee. The directory is marked excluded from iCloud backup, so a few hundred megabytes of comics never inflate the reader's backup.

The engine runs in the **foreground only**: backgrounding the app pauses it, returning resumes. Resume is **page-level** — a page already on disk is skipped, so an interrupted chapter costs only what had not yet arrived, which matters when a chapter is 60–180 separate requests. Four fetches run at once, matching the image cache's existing in-flight limit and its reasoning: at ~100 KB a page, a fetch costs round-trip latency rather than bandwidth. Requests are built through the same shared authorized-request path as every other backend call, so Cloudflare Access headers are attached exactly as they are everywhere else. A chapter is marked complete only when every page is present.

**A temporary hard stop at 20 chapters is part of this ticket.** It refuses further downloads rather than evicting anything — real first-in-first-out eviction is ticket 04, and it deserves its own ticket because it is the only irreversible, destructive logic in the feature. The stop exists so that the device cannot be filled with several gigabytes in the window between this ticket and that one. Ticket 04 replaces it.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A chapter row in the chapter list offers a download action and shows its state: not downloaded, downloading with progress, downloaded
- [ ] Downloading fetches every page of the chapter and stores it on the device
- [ ] A chapter is marked complete only once every page is present
- [ ] Downloading can be cancelled, and cancelling deletes the partial chapter
- [ ] An interrupted download resumes without re-fetching pages already on disk
- [ ] Backgrounding the app pauses the download; returning resumes it
- [ ] Downloaded state survives closing and relaunching the app
- [ ] At most four page fetches are in flight at once
- [ ] Download requests carry the Cloudflare Access headers
- [ ] Content is stored under Application Support, not Caches, and is excluded from iCloud backup
- [ ] Each downloaded chapter carries a record holding its ordered page URLs, page count, titles, ids, started-at time and completion state
- [ ] A download beyond 20 chapters is refused rather than evicting anything
- [ ] The store is exercised in tests against an injected temporary directory, never the real Application Support path
- [ ] Reading, progress reporting, prefetching and selection are unaffected
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout
