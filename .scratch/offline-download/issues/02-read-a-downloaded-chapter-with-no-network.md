# 02 — Read a downloaded chapter with no network

**What to build:** The reader turns on airplane mode, opens the app, browses 書庫 as usual, taps a chapter they downloaded, and reads it from beginning to end. A chapter they did not download tells them so in plain words rather than failing as though the app were broken.

Today none of that is possible, and the reason is easy to miss: it is the metadata, not the bytes. The library screen, the comic detail the Reader needs to resolve its chapter list, and above all the reader request that is **the only source of a chapter's ordered page URLs** are three separate live calls. Without them, twenty downloaded chapters are unreachable.

Two changes deliver it, and neither touches a screen.

**The image path consults the disk before the network.** The image cache resolves a URL through a single fetch path; that path gains one step in front — ask `OfflineChapterStore` first, fall through to the network on a miss. Everything downstream is untouched: the prefetch window, the in-flight limits, failure marking, forced decoding, and the synchronous memory-hit path that keeps a cached page from flashing. The Reader gains no offline code path at all, which is the point — there is no second way for it to be wrong. A downloaded page therefore also loads from disk when the connection is fine, which is faster and cheaper.

**Writing is deliberately not symmetric: only the download engine writes to disk, and the read path never populates it.** This is the invariant the whole feature rests on. The moment a page merely read gets written, three things that must agree stop agreeing — what the 已下載 list shows, what counts against the cap, and what is actually on the device — and every statement the app makes about what is available offline becomes untrue.

**The repository grows an offline fallback, as a decorator.** A decorator wrapping the live API repository adds the behaviour without changing the `ComicRepository` protocol, so 書庫, the chapter list and the Reader keep depending on exactly what they depend on today. Successful library and comic-detail responses have their **raw bytes** stored and are decoded from storage when the network fails — raw bytes rather than re-encoded models, because the display models are decode-only, so this needs no new conformance and no model change anywhere. The reader request falls back differently: it answers from a **completed** chapter record, which is what that record was built to make possible.

A chapter that was never downloaded, or only partly downloaded, still fails — but as a distinguishable "not available offline" outcome that the Reader presents as such, not as the generic connection error that today would leave the reader guessing whether the app or the network is at fault.

**The fallback must not mask a live failure.** A real server error while the connection is up should still surface as an error. Silently serving a stale catalog that looks perfectly fine is worse than an honest failure, because nothing about the screen tells the reader they are looking at yesterday's library.

**Blocked by:** 01 — Download a chapter to the device.

**Status:** implemented on branch `feat/offline-read`, 2026-08-18 — unit-verified, awaiting the repo owner's airplane-mode device pass. **One acceptance criterion is not met: covers do not render offline** (see "What is not delivered" below); that decision is the repo owner's.

- [~] With no connection, 書庫 renders from the last successful responses instead of an error screen, **including chapter lists and the download markers — but not covers** (see below)
- [x] With no connection, a completed downloaded chapter opens and reads from first page to last
- [x] With no connection, a chapter that was never downloaded shows an explicit not-available-offline message, distinct from a connection error
- [x] A partially downloaded chapter is treated as not available offline
- [x] A downloaded page is served from disk with no network request issued, even when the connection is available
- [x] A page that was not downloaded still goes to the network exactly as before
- [x] Reading a page never writes it to disk
- [x] A genuine server error while connected surfaces as an error rather than silently serving stored responses
- [x] Successful responses refresh what is stored, so the offline library reflects the last time the app was online
- [x] Selection, recognition and on-device translation work normally on a downloaded page
- [x] Prefetching, retention, progress reporting and preview (peek) mode are unaffected
- [x] The fallbacks are tested by injecting a failing inner repository rather than by stubbing the network, and the disk-first image path is tested by asserting no request was issued
- [x] No XCUITest is written; a device checklist is handed to the repo owner, centred on a full airplane-mode round trip

## What was built

- `CatalogSnapshotStore.swift` — the raw bytes of the last successful `GET /comics` and `GET /comics/{id}`, one small file each under Application Support, excluded from backup. Written by `APIComicRepository` because a decorator never sees bytes; it is handed decoded models, and those models are `Decodable` only.
- `OfflineFallbackComicRepository.swift` — the decorator. `library()` and `comic(id:)` replay stored bytes; `readerChapter` answers from a **completed** chapter record; `rescan()` and `saveProgress` pass straight through. `ComicRepository` is untouched, so no screen changed.
- `PageImageCache` — one step in front of the network inside the single fetch closure every caller already went through. Prefetch, in-flight limits, failure marking, forced decoding and the synchronous memory-hit path are all downstream of it and unchanged.
- `OfflineChapterStore.pageData(for:)` — keyed by URL alone, since that is all the image cache knows. There is deliberately no write counterpart.
- `ErrorStateView` gains a `.notAvailableOffline` kind; the Reader picks it when the failure is `OfflineReadError`.

**Only a transport failure counts as "offline".** `URLError` — what airplane mode, a dead tunnel and a timeout all produce — falls back; a 500, a Cloudflare Access rejection and an undecodable response are rethrown. Serving yesterday's library after a real server error would look perfectly fine on screen and be silently out of date, with nothing to tell the reader.

## What is not delivered

**Covers do not render with no connection.** A cover's bytes are only ever in the memory cache, which does not survive a relaunch, and the disk holds exactly what was downloaded on purpose — a comic's cover and a chapter's thumbnail are neither. Offline, 書庫 and the chapter list therefore render fully — titles, chapter counts, read state, download markers, and every chapter tappable — with placeholder artwork.

Closing it needs a decision rather than a patch, which is why it is not quietly included here: a cover cache is **unbounded**. At this library's size it is 300+ comic covers and 3,000+ chapter thumbnails at roughly 100 KB each — plausibly 300 MB, well past the 100–400 MB the twenty-chapter cap was sized for — so it needs a budget and an eviction rule of its own, and those are the kind of thing this spec deliberately gave its own ticket. Options, for the repo owner:

1. Accept placeholders offline (nothing to build).
2. A small bounded cover cache — covers only, never pages, its own byte budget, LRU — as its own ticket. It would not touch the download cap or the 已下載 list, so the invariant that the disk holds exactly what was downloaded stays true of *downloads*.

## Verification

`BUILD SUCCEEDED`, and the whole `vista_comicTests` target passes, including 12 new tests in `OfflineReadTests`: the library and comic detail replaying stored bytes when offline; a 500 and a bare offline-with-nothing-stored both still failing; a successful response being what refreshes storage, and the reader endpoint deliberately not being stored; a downloaded chapter opening from its record; never-downloaded and partly-downloaded both reporting not-available-offline; a server error surfacing even for a downloaded chapter; a downloaded page resolving with **no request issued**; a non-downloaded page still going to the network; and reading a page never writing it to disk.

The fallbacks are driven by a failing inner repository rather than a stubbed network, per this ticket's own testing decision.

## Device checklist for the repo owner

A full airplane-mode round trip, on one compact phone and one larger phone:

1. Online, download two chapters of one comic. Force-quit the app.
2. Turn on airplane mode, launch: 書庫 lists the comics with titles, chapter counts and last-read as before (artwork will be placeholders — see above).
3. Open the comic: the chapter list is there, and the download markers are correct.
4. Open a downloaded chapter and read it from the first page to the last — no spinner that never resolves, no failed pages.
5. Open a chapter that was **not** downloaded: it says 尚未下載 with an explanation, not the generic 無法連線 error.
6. Selection, OCR and on-device translation on a downloaded page behave exactly as online. (Anything that needs the cloud — 深入解釋 — is expected to fail.)
7. Turn airplane mode off, pull to refresh: the real library comes back.
8. **Still online**, open a downloaded chapter: pages appear noticeably faster than an undownloaded chapter, and stay correct.
9. Stop the backend while connected (or point it at a dead host): the app shows the connection error rather than silently serving the stored library.
