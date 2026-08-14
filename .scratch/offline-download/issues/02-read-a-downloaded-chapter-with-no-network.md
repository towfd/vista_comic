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

**Status:** ready-for-agent

- [ ] With no connection, 書庫 renders from the last successful responses instead of an error screen, including covers and chapter lists
- [ ] With no connection, a completed downloaded chapter opens and reads from first page to last
- [ ] With no connection, a chapter that was never downloaded shows an explicit not-available-offline message, distinct from a connection error
- [ ] A partially downloaded chapter is treated as not available offline
- [ ] A downloaded page is served from disk with no network request issued, even when the connection is available
- [ ] A page that was not downloaded still goes to the network exactly as before
- [ ] Reading a page never writes it to disk
- [ ] A genuine server error while connected surfaces as an error rather than silently serving stored responses
- [ ] Successful responses refresh what is stored, so the offline library reflects the last time the app was online
- [ ] Selection, recognition and on-device translation work normally on a downloaded page
- [ ] Prefetching, retention, progress reporting and preview (peek) mode are unaffected
- [ ] The fallbacks are tested by injecting a failing inner repository rather than by stubbing the network, and the disk-first image path is tested by asserting no request was issued
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, centred on a full airplane-mode round trip
