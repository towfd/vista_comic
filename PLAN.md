# vista_comic development plan

Last updated: 2026-07-22

## Current status

- Milestones M1–M4 are complete; the local UI release goal is met (localization + auto-advance also shipped).
- Active milestone: **M5 — Local backend (folder → app)**, at Slice 0 (contract + folder validation). Backend design of record: `docs/backend-architecture.md`.
- Current owner: Coordinator (delegates to `backend-implementer`, `frontend-implementer`, `code-reviewer`).
- Next action: validate the confirmed folder format against the real local library (read-only), then build Slice 1 (in-memory catalog API).

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
- Web scraping and real URL parsing (README §2 URL import remains later work)
- Authentication and cloud sync (a local, read-only backend for a developer manga folder is now in scope — see M5)
- Persistence beyond what M5 needs (reading-progress store arrives at M5 Slice 4)
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

Additional reader tasks (requested 2026-07-21):

- [deferred] Remember the last-read position within each chapter. An in-session-only version has little value, so this is deferred to the future persistence/backend milestone where it can be designed to survive app launches.
- [x] At the bottom of a chapter, pulling *past* the end (overscroll) advances to the next chapter (auto-advance). Respect the last-chapter boundary. Pure UI, no backend. (`ComicView` uses `.onScrollGeometryChange`; requires an overscroll of `pullThreshold` past the bottom so merely reaching the end doesn't jump; only for content taller than the screen; `nextChapter == nil` is a no-op.)

Acceptance criteria for the additional tasks:

- [x] Pulling past the bottom of a chapter moves the reader into the next chapter, and does nothing on the last chapter. (build-verified; behaviour to be confirmed by the user on-device)

### M4 — Integration review

- Status: Complete
- Owner: Coordinator and Code reviewer
- Dependencies: M2 and M3

Tasks:

- [x] Integrate the library, chapter, and reader flows. (all merged to `main`)
- [x] Run available builds and SwiftUI previews. (`BUILD SUCCEEDED` on integrated `main`)
- [x] Check compact and larger iPhone layouts. (iPhone SE + iPhone 16 Pro Max)
- [x] Check dark mode, Dynamic Type, and accessibility labels. (dark-mode + max-Dynamic-Type screenshots on iPhone SE; reader controls have labels)
- [x] Review and assign confirmed findings. (fixed P2 below; P3s recorded as backlog)

Findings:

- [x] **P2 (fixed)** — Continue button used a hardcoded `.background(.white)`, rendering as a white block in dark mode. Now `Color(.systemBackground)`, verified adaptive in a dark-mode screenshot.
- [ ] **P3 (backlog)** — Text uses fixed font sizes (`AppFont`, inline `.system(size:)`), so it does not scale with Dynamic Type (confirmed unchanged at the max accessibility size). Move to relative text styles later.
- [ ] **P3 (backlog)** — `grayFont` / `primaryRed` / `AccentColor` have no dark-appearance variant (readable in dark, but not tuned).

Acceptance criteria:

- [x] The complete sample-data flow is demonstrable.
- [x] No confirmed high-severity UI or navigation issue remains. (only the P2 dark-mode issue, now fixed)
- [x] Verification results and environment limitations are documented.

### M5 — Local backend (folder → app)

- Status: In progress (Slice 0)
- Owner: Coordinator; implemented by `backend-implementer` (backend) and `frontend-implementer` (iOS)
- Dependencies: M1–M4
- Contract of record: `docs/backend-architecture.md` (confirmed decisions + API shape). Scope: a local, read-only "scan-and-serve" backend that makes a developer's manga folder appear in the app. Cloud sync / auth / URL import remain out of scope.
- Config: the library path lives only in a gitignored `.env` (`MANGA_LIBRARY_PATH`); never commit it.

Slices (each ships only after the prior one has an observable acceptance test):

- [ ] **Slice 0 — contract + folder validation** (Coordinator / `service-explorer`, read-only). Validate the confirmed folder format against the real library; lock the API contract and stable, path-derived IDs.
  - Acceptance: the real folder structure matches the recorded format, or differences are reconciled into the doc.
- [ ] **Slice 1 — in-memory catalog API** (`backend-implementer`, new `backend/`). FastAPI scans `MANGA_LIBRARY_PATH` into memory; serves `GET /comics`, `GET /comics/{id}`.
  - Acceptance: `curl /comics` counts match the folder; a re-run is byte-identical; never writes to the library.
- [ ] **Slice 2 — page images + reader endpoint** (`backend-implementer`). `GET /comics/{id}/chapters/{cid}` + `GET /media/...`.
  - Acceptance: opening a page URL in a browser shows the correct image in correct order.
- [ ] **Slice 3 — iOS consumes it** (`frontend-implementer`; `Shared/Models.swift` URL retype is a coordinator-owned change). Repository + `HomeView` data-source swap + three `Image → AsyncImage` sites + catalog loading/error states.
  - Acceptance: the app shows the folder's comics, opens a chapter, and scrolls real pages, with loading and failure states.
- [ ] **Slice 4 — reading-position persistence** (`backend-implementer` + `frontend-implementer`). A small `progress` store (PostgreSQL or SQLite); catalog stays scan-derived; `readState` / `lastReadAt` become live.
  - Acceptance: read part of a chapter, restart, and resume at the saved position.

Load-bearing: server IDs must be stable across scans/restarts (path-derived hash), because Slice 4 keys progress on them.

## Known issues and constraints

- Xcode builds may report simulator-service or cache permission limitations in restricted execution environments.
- `LibraryFlowUITests` and `ReaderFlowUITests` now cover the core flow; the original unit/UITest boilerplate is still unused.
- Comic and chapter titles in `SampleData` are English placeholders (data, not UI chrome) and are intentionally not localized.
- The manga library path is machine-specific config kept only in a gitignored `.env` (`MANGA_LIBRARY_PATH`); it must never appear in committed files.

## Open decisions

- [x] First-release UI language: **Traditional Chinese (繁體中文)** (resolved 2026-07-21), delivered **localization-ready via a String Catalog — not hardcoded** (see Pending cross-cutting work). On-screen text only, not the SwiftUI framework.
- [x] User-facing section name: **Library** (resolved 2026-07-21) — renders as **書庫** under the Traditional Chinese UI. Keep internal filenames and types (`FavouriteView`, `FavouriteView.swift`, …) for now.

## Cross-cutting work

- [x] Localization-ready UI with Traditional Chinese — **no hardcoded Chinese** (done 2026-07-21). `Localizable.xcstrings` holds English development keys + 繁中 translations; `readStateLabel` / `lastReadText` use `String(localized:)`; `.accessibilityLabel` values are English keys; `zh-Hant` added to `knownRegions`. Follows the device language (English base, 繁中 first translation) — adding a language later is just a catalog column.
  - Verified: `BUILD SUCCEEDED`; launched with `-AppleLanguages (zh-Hant)` and confirmed 書庫 / 繼續閱讀 / 章節（N） / 尚未開始 / locale-formatted date render; `LibraryFlowUITests` + `ReaderFlowUITests` pass (forced English).

## Next action

M5 is active at Slice 0: validate the confirmed folder format in `docs/backend-architecture.md` against the real local library (read-only), then dispatch `backend-implementer` for Slice 1 (in-memory catalog API). Each slice gets a coordinator-approved plan before implementation.

Backlog (unstarted): Dynamic Type support (move off fixed font sizes); dark-appearance colour variants; README §2 URL import.
