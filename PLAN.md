# vista_comic development plan

Last updated: 2026-07-21

## Current status

- Active milestone: M1 — Shared UI foundation
- Status: Complete (shared contract in place; simulator tap-through not yet run)
- Current owner: Coordinator
- Next action: assign M2 (Library) and M3 (Reader) as non-overlapping parallel work on the shared contract.

## Current release goal

Complete a demonstrable local UI flow:

```text
Comic library
→ Choose a comic
→ Browse chapters
→ Open a chapter
→ Read vertically scrolling comic images
→ Show or hide reader controls
```

The flow must work with sample data and without a backend or network dependency.

## In scope

- Comic library UI
- Comic and chapter presentation
- Chapter navigation
- Vertical comic image reader
- Basic reader controls
- Local sample data and UI state
- Integration and UI review

## Temporarily out of scope

- OCR and text-region selection
- Translation or LLM integration
- Web scraping and real URL parsing
- Backend APIs, authentication, and cloud sync
- Persistence beyond what is necessary for the UI prototype
- Architecture added only for hypothetical future requirements

Future functionality may use simple placeholders only when the current UI flow needs an entry point.

## Existing work to protect

- Preserve all user changes already present in the working tree.
- Inspect the diff before editing `HomeView.swift` or `Features/ComicPage/ComicView.swift`; both currently contain uncommitted work.
- Keep the existing Favourite, ChapterPage, and ComicPage feature split unless a focused rename clearly improves the current flow.
- Reuse current image and color assets where practical.

## Milestones

### M1 — Shared UI foundation

- Status: Complete
- Owner: Coordinator
- Dependencies: None

Tasks:

- [x] Add small comic and chapter display models. (`Shared/Models.swift`: `Comic`, `Chapter`, `ReadState`)
- [x] Add consistent sample data. (`Shared/SampleData.swift`)
- [x] Establish `NavigationStack` routes for library, chapter list, and reader. (value-based `.navigationDestination(for:)` in `HomeView`; the reader route is `ReaderRoute { comic, chapter }` so the reader can access sibling chapters)
- [x] Define the minimum shared visual tokens needed by multiple screens. (`Shared/AppTheme.swift`: `AppFont`)
- [x] Verify existing user changes remain intact. (`.gitignore`, `README.md`, and the user's `ComicView`/`HomeView` intent preserved)

Acceptance criteria:

- [x] The same sample data drives the library, chapter list, and reader.
- [x] The app can navigate from the library to a chapter list and reader. (contract compiles; interactive simulator tap-through not yet run)
- [x] Shared contracts are stable enough for Library and Reader agents to work independently.
- [x] The project builds or any environment limitation is documented. (`xcodebuild ... -scheme vista_comic` → **BUILD SUCCEEDED**, Xcode 16.1, iOS 18.1 simulator SDK)

### M2 — Library and chapter experience

- Status: Complete (build + simulator verified)
- Owner: Library agent
- File ownership: `Features/Favourite/` and `Features/ChapterPage/`
- Consumes (do not change): `Shared/Models.swift`, `Shared/SampleData.swift`, `Shared/AppTheme.swift`, and the `HomeView` navigation contract.
- Note: `Comic` now carries `lastReadAt: Date?`; `ComicListView` renders it. After review, `Shared/SampleData.swift` was made self-consistent — an unstarted comic (`lastReadAt == nil`) keeps every chapter unread.

Tasks:

- [x] Make library and chapter components data-driven. (done across M1 and M2)
- [x] Support populated and empty library states. (`FavouriteView` shows a vertically centred `ContentUnavailableView` when `comics.isEmpty`)
- [x] Support unread, reading, and read chapter presentation. (`ChapterListView` shows state-specific label, icon, and colour)
- [x] Verify library-to-chapter and continue-reading navigation. (verified on iPhone SE + iPhone 16 Pro Max, iOS 18.1; `LibraryFlowUITests` drives library → chapter list → reader and back, and passes)

Acceptance criteria:

- [x] Users can choose a comic and chapter from sample data.
- [x] Empty and populated states render correctly. (populated + empty `#Preview` added; build-verified)
- [x] Continue Reading opens the expected chapter. (`ComicListView` navigates to the in-progress chapter, else first unread, else first)

### M3 — Reader experience

- Status: Core complete (build + simulator verified); additional reader tasks below are pending
- Owner: Reader agent
- File ownership: `Features/ComicPage/`
- Consumes (do not change): `Shared/Models.swift` (`Chapter.pageImageNames`, `ReaderRoute`), `Shared/AppTheme.swift`, and the `HomeView` navigation contract.

Tasks:

- [x] Render multiple vertically scrolling comic images from sample data.
- [x] Show and hide reader controls. (tap to toggle; system nav bar hidden; back / list buttons carry accessibility labels; control-bar material now extends into the top/bottom safe areas)
- [x] Support back, chapter list, previous chapter, and next chapter actions. (custom back, chapter-list sheet, and previous/next controls in the bottom bar; scroll resets to the first page on chapter change)
- [x] Handle first and last chapter boundaries. (previous is disabled on the first chapter, next on the last)
- [~] Add placeholder loading and failure states. (failure placeholder done and reachable via a missing asset; a loading state is deferred to the future asynchronous image-loading milestone, since local assets load synchronously)

Acceptance criteria:

- [x] Comic images form a continuous vertical reading experience.
- [x] Reader controls remain usable within safe areas.
- [x] Previous and next chapter behavior handles boundaries correctly. (verified by `ReaderFlowUITests` on iPhone SE, iOS 18.1)

Additional reader tasks (requested 2026-07-21, no backend required):

- [ ] Remember the last-read position within each chapter and resume there when the chapter is reopened. In-session (in-memory) only for now; persisting across app launches needs storage and is deferred to a later persistence/backend milestone.
- [ ] When the reader is scrolled to the bottom of a chapter, continue into the next chapter (auto-advance / continuous reading). Respect the last-chapter boundary. Pure UI, no backend.

Acceptance criteria for the additional tasks:

- Reopening a chapter returns to the last-read position within the same app session.
- Reaching the bottom of a chapter moves the reader into the next chapter, and does nothing on the last chapter.

### M4 — Integration review

- Status: Not started
- Owner: Coordinator and Code reviewer
- Dependencies: M2 and M3

Tasks:

- [ ] Integrate the library, chapter, and reader flows.
- [ ] Run available builds and SwiftUI previews.
- [ ] Check compact and larger iPhone layouts.
- [ ] Check dark mode, Dynamic Type, and accessibility labels.
- [ ] Run `$review-vista-comic-code` and assign confirmed findings to the existing owners.

Acceptance criteria:

- The complete sample-data flow is demonstrable.
- No confirmed high-severity UI or navigation issue remains.
- Verification results and environment limitations are documented.

## Known issues and constraints

- Xcode builds may report simulator-service or cache permission limitations in restricted execution environments.
- The current unit and UI tests are still boilerplate and do not yet verify product behavior.
- UI strings are currently English and need a one-off localization pass to Traditional Chinese (see Open decisions).

## Open decisions

- [x] First-release UI language: **Traditional Chinese (繁體中文)** (resolved 2026-07-21), delivered **localization-ready via a String Catalog — not hardcoded** (see Pending cross-cutting work). On-screen text only, not the SwiftUI framework.
- [x] User-facing section name: **Library** (resolved 2026-07-21) — renders as **書庫** under the Traditional Chinese UI. Keep internal filenames and types (`FavouriteView`, `FavouriteView.swift`, …) for now.

## Pending cross-cutting work

- [ ] Make the UI localization-ready and provide Traditional Chinese — **do not hardcode Chinese**. Approach:
  - Add a `Localizable.xcstrings` String Catalog; keep `Text("…")` literals as **English development keys** and supply 繁中 translations (書庫, 繼續閱讀, 未讀/閱讀中/已讀, …).
  - Fix `String`-typed values that `Text` will not auto-localize — `ChapterListView.readStateLabel`, `ComicListView.lastReadText` (interpolated), and similar — using `String(localized:)` / `LocalizedStringResource`.
  - Keep `.accessibilityLabel` values as localized keys too.
  - Update `LibraryFlowUITests` / `ReaderFlowUITests`, which currently assert English strings (prefer accessibility identifiers over visible text where practical, so they survive language changes).
  - Follow the device language by default (English keys as base, 繁中 as the first translation); adding another language later is only a new catalog column, no refactor.
  - Cross-cutting across `Features/Favourite/`, `Features/ChapterPage/`, and `Features/ComicPage/`; coordinator-owned; best done as one focused change after M3 merges.

## Next action

M1 is complete and the shared contract is stable. Assign M2 (Library, owns `Features/Favourite/` + `Features/ChapterPage/`) and M3 (Reader, owns `Features/ComicPage/`) as non-overlapping parallel work. Optionally run an interactive simulator tap-through to confirm the library → chapter list → reader path at runtime before feature work begins.
