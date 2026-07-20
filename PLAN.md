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

- Status: Ready (unblocked by M1)
- Owner: Library agent
- File ownership: `Features/Favourite/` and `Features/ChapterPage/`
- Consumes (do not change): `Shared/Models.swift`, `Shared/SampleData.swift`, `Shared/AppTheme.swift`, and the `HomeView` navigation contract.
- Note: `Comic` now carries `lastReadAt: Date?`; `ComicListView` renders it (real reading-progress logic is still M2).

Tasks:

- [ ] Make library and chapter components data-driven.
- [ ] Support populated and empty library states.
- [ ] Support unread, reading, and read chapter presentation.
- [ ] Verify library-to-chapter and continue-reading navigation.

Acceptance criteria:

- Users can choose a comic and chapter from sample data.
- Empty and populated states render correctly.
- Continue Reading opens the expected chapter.

### M3 — Reader experience

- Status: In progress (reader chrome started by Coordinator via a direct user request)
- Owner: Reader agent
- File ownership: `Features/ComicPage/`
- Consumes (do not change): `Shared/Models.swift` (`Chapter.pageImageNames`, `ReaderRoute`), `Shared/AppTheme.swift`, and the `HomeView` navigation contract.

Tasks:

- [x] Render multiple vertically scrolling comic images from sample data.
- [x] Show and hide reader controls. (tap to toggle; system nav bar hidden for immersive reading; back / list buttons carry accessibility labels; safe-area refinement still pending)
- [~] Support back, chapter list, previous chapter, and next chapter actions. (back + chapter-list sheet with in-place chapter switching done; scroll resets to the first page on chapter change; previous / next chapter still pending)
- [ ] Handle first and last chapter boundaries.
- [ ] Add placeholder loading and failure states.

Acceptance criteria:

- Comic images form a continuous vertical reading experience.
- Reader controls remain usable within safe areas.
- Previous and next chapter behavior handles boundaries correctly.

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
- UI language and the user-facing label for the existing Favourite feature remain product decisions.

## Open decisions

- [ ] Choose the first-release UI language.
- [ ] Decide whether the user-facing section should be called Library or Favourite while preserving internal filenames initially.

## Next action

M1 is complete and the shared contract is stable. Assign M2 (Library, owns `Features/Favourite/` + `Features/ChapterPage/`) and M3 (Reader, owns `Features/ComicPage/`) as non-overlapping parallel work. Optionally run an interactive simulator tap-through to confirm the library → chapter list → reader path at runtime before feature work begins.
