# 07 — Jump from a saved translation back to its source page

**What to build:** in the 單字本 tab (Ticket 06), each saved-translation row gets a button that opens the reader directly at the comic/chapter/page it was saved from, so the user can revisit the original context without navigating there manually.

**Blocked by:** 06 (needs the real list to attach a button to)

**Status:** resolved

- [x] Each row in `VocabularyView`'s list has a button (not the whole row) that opens `ComicView` at `comicID`/`chapterID`/`pageNumber` from that `SavedTranslation` — `SavedTranslationRow`'s trailing `NavigationLink(value:)`, tap target is just the icon
- [x] `VocabularyView` gets its own `NavigationStack` + `navigationDestination(for: ReaderRoute.self)`, independent of the 書庫 tab's stack
- [x] `ReaderRoute` gains an optional `targetPage: Int?` and `isPeek: Bool` (default `nil`/`false`, existing call sites in `ComicListView`/`ChapterListView` unchanged)
- [x] Opening the reader this way is a **read-only preview**: `ReaderView.sendProgress` (the single choke point every progress write funnels through — scroll debounce, flush-on-leave, restart-on-advance) no-ops when `isPeek`
- [x] Lightweight visual indication: "Preview — progress won't be saved" under the chapter title in the bottom control bar, only when `isPeek`

## Comments

Implementation touched `Shared/Models.swift` (`ReaderRoute`), `HomeView.swift` (pass-through in its own `navigationDestination`), `Features/ComicPage/ComicView.swift` (`ComicView`/`ReaderView` accept `targetPage`/`isPeek`; `loadPages` uses `targetPage` as a one-shot resume override, consumed on first chapter open only), and `Features/Vocabulary/VocabularyView.swift` + `SavedTranslationRow.swift`.

**Manual verification**: confirmed on booted iOS 18.1 simulators (iPhone SE, iPhone 16 Pro Max) against the real backend — tapping the jump button on a saved entry opens the reader at the exact saved comic/chapter/page, shows the "Preview — progress won't be saved" indicator, and (by code inspection, matching `sendProgress`'s single gate) never calls `saveProgress`. Verified by temporarily forcing navigation (this sandboxed environment has no tap-automation tool — see `tab-bar-navigation` ticket 01's comments on the same limitation) and reverting immediately after — no residue in the diff.

## Comments

Design discussion (2026-07-30, with the user): considered pushing onto the 書庫 tab's existing `NavigationStack` (would require hoisting shared navigation state to `RootTabView`) vs. giving 單字本 its own independent stack and opening a second `ComicView` instance there. Chose the latter — smaller change, no cross-tab state coupling, and tabs already behave as independent navigation contexts elsewhere in the app.

The progress-overwrite risk was flagged proactively (not something the user asked about first): `ReaderView` unconditionally calls `saveProgress` on scroll, so without `isPeek`, browsing back to an earlier saved page from 單字本 would silently rewind the chapter's stored resume position. User confirmed: preview should not touch progress.
