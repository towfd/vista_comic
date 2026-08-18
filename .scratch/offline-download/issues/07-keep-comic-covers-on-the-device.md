# 07 — Keep each comic's cover on the device

**What to build:** With no connection, 書庫 looks like 書庫 — the covers are there, not a grid of placeholders. This closes the one acceptance criterion ticket 02 could not meet.

**Comic covers only. Chapter thumbnails are explicitly out.** That is the whole reason this is a small ticket rather than the storage problem ticket 02 declined to solve quietly: a comic's cover is one image per comic, so the cache is exactly as large as the library and grows only when the library does. Chapter thumbnails are one per chapter — 3,000+ at this library's size, plausibly 300 MB, past the budget the entire twenty-chapter download cap was sized against. The chapter list keeps its placeholders offline, and that is a deliberate trade rather than an omission: the reader recognises a comic by its cover, and a chapter by its number.

**Nothing extra is fetched.** A cover is kept when it is fetched to be *displayed* — scrolling 書庫 is what fills the cache. Warming it by requesting every comic's cover up front was considered and rejected: it would spend a few hundred requests on comics the reader may never open, and the covers that matter are the ones they scroll past anyway.

**What counts as a comic cover is answered by the catalog, not guessed from the URL.** The image cache has no opinion about what an image depicts — one instance and one budget serve pages and covers alike, deliberately — so it cannot be the thing that decides. The library response knows: every `Comic.coverURL` in it is a comic cover, and nothing else is. The cache is told that set whenever a library response is decoded, from either the live call or the stored one.

**That set is also the eviction rule.** Files whose URL is no longer a cover in the current library are removed when the set changes, so a comic leaving the library stops costing anything and no byte budget or LRU is needed. The bound is structural: one file per comic, or fewer.

**This is a second store, and it must not be confused with the first.** `OfflineChapterStore` holds what the reader deliberately downloaded, and the rule that only the download engine writes to it is what keeps the 已下載 list, the cap and the device in agreement. The cover cache is a separate store that counts against neither, so writing to it on a read changes nothing about any statement the app makes about downloads.

**Blocked by:** 02 — Read a downloaded chapter with no network.

**Status:** implemented on branch `feat/offline-covers`, 2026-08-18 — unit-verified, awaiting the repo owner's airplane-mode relaunch. Raised by the repo owner while device-testing ticket 02: *"我們可以只快取 cover 嗎，每部漫畫的封面就好"* — which is what makes it a small ticket rather than the storage problem ticket 02 declined to solve.

- [x] With no connection, every comic in 書庫 shows its cover after a relaunch
- [x] A cover is kept only when it was fetched to be displayed; nothing is requested that would not have been requested anyway
- [x] Only comic covers are kept — a chapter thumbnail is never written
- [x] Covers that are no longer in the library are removed when the library changes
- [x] A cover already on the device is served without a network request
- [x] Downloaded pages, the download cap and the 已下載 accounting are unaffected — the two stores are separate
- [x] Covers live under Application Support and are excluded from iCloud backup
- [x] No XCUITest is written; the device check is an airplane-mode relaunch with 書庫 fully drawn

## What was built

- `Networking/CoverCache.swift` — the seam, `FileCoverCache` (one file per cover under Application Support, excluded from backup) and an in-memory double for previews and the launch fallback.
- `PageImageCache` consults it after the chapter store and before the network, and writes to it after a successful fetch — a call that no-ops unless the catalog has said the URL is a comic's cover, so the filtering lives in the store rather than at a call site that genuinely does not know what it just downloaded.
- `AuthorizedAsyncImage.FetchedImage` now carries the response bytes, so what is kept is what the server sent rather than a PNG re-encoding of the decode.
- `OfflineFallbackComicRepository.library()` declares the cover set on both the live and the replayed path.

**The membership rule is the whole design.** The image cache has no opinion about what an image depicts — one instance and one budget serve pages and covers alike, deliberately — so it cannot be the thing that decides. The library response can: every `Comic.coverURL` in it is a comic cover and nothing else is. That same set is the eviction rule, which is why this needs no byte budget and no LRU: the cache is exactly as large as the library, and a comic leaving it takes its cover with it.

**Two stores, kept apart.** Writing on a read is safe here precisely because this is *not* `OfflineChapterStore`. A cover occupies no slot, appears in no 已下載 list, and counts against no cap, so nothing the app says about downloads changes.

## Verification

`BUILD SUCCEEDED`, whole `vista_comicTests` target passes, including 8 new tests in `CoverCacheTests`: a cover fetched for display is served from disk after a relaunch with **no request issued**; a chapter thumbnail fetched the same way is never written; covers dropped from the library are deleted, bytes and all; an undeclared URL is not kept even if it will be a cover later; both the live and the replayed library declare the set; keeping a cover leaves the chapter store empty; and the directory is under Application Support and excluded from backup.

## Device check for the repo owner

Online, scroll 書庫 so every cover has been drawn at least once. Force-quit, turn on airplane mode, relaunch: 書庫 is drawn with its covers. Chapter thumbnails are still placeholders, by design. Compact and larger phone.
