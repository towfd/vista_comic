# vista_comic roadmap

> **Roadmap & history only.** Active work — specs, tickets, task status, and the next action — now lives as local markdown under `.scratch/<feature>/` (see `docs/agents/issue-tracker.md`). This file records milestone history and long-range direction; do not treat it as the live task tracker.

Last updated: 2026-08-09

## Current status

- Milestones M1–M10 are complete; **M10 (comprehension response UX) is merged** — all 10 implementation tickets resolved, PRs [#38](https://github.com/towfd/vista_comic/pull/38)–[#48](https://github.com/towfd/vista_comic/pull/48) merged into `main` on 2026-08-06.
- M5 (local backend) is fully complete, including Slice 4 (reading-progress persistence) and the `remote-access` connectivity work (Cloudflare Tunnel + Access — tracked under `.scratch/remote-access/`, not a separate `ROADMAP.md` slice, per the ticket-driven workflow established in PR #19).
- Active work now runs on the ticket-driven workflow: specs and tickets live under `.scratch/<feature>/` (see `docs/agents/issue-tracker.md`); this file only records milestone history once a feature ships.
- Current owner: main Claude Code session (delegates to `backend-implementer`/`frontend-implementer` sub-agents per increment).
- The OCR text-editing defect is **fixed** ([#50](https://github.com/towfd/vista_comic/pull/50)), which closes the last of the three problems reported alongside M10's two.
- **Alembic owns the schema** ([#55](https://github.com/towfd/vista_comic/pull/55), 2026-08-07) — the migration tool M10 made conditional on its own schema landing. `docs/manual-migrations.md` is closed.
- **Reader page prefetch is merged** ([#60](https://github.com/towfd/vista_comic/pull/60), 2026-08-09) — Page images are cached and prefetched ahead of the reader, so scrolling no longer waits. Tracked under `.scratch/reader-page-prefetch/`. No milestone is in progress; next action is unclaimed.

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

> This list described the original M1–M4 sample-data-only release goal above. M5–M8 have since shipped a real backend, OCR, and translation — kept here as historical record of that release goal, not current scope. See the Milestones section for what's actually shipped.

- ~~OCR and text-region selection~~ — shipped, M6
- ~~Translation or LLM integration~~ — on-device translation shipped, M8; cloud LLM comprehension (translation + grammar/context/tone explanation) shipped, M9
- Web scraping and real URL parsing (README §2 URL import remains later work)
- ~~Authentication and cloud sync~~ — Cloudflare Access authentication shipped (`.scratch/remote-access/`); cloud *sync* (README roadmap item 5) remains out of scope
- ~~Persistence beyond what M5 needs~~ — reading-progress (M5 Slice 4) and saved translations (M8) both shipped
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

- Status: Complete (all 5 slices merged)
- Owner: Coordinator; implemented by `backend-implementer` (backend) and `frontend-implementer` (iOS)
- Dependencies: M1–M4
- Contract of record: `docs/api-contract.md` (API shape + folder format), `docs/adr/` (confirmed decisions). Scope: a local, read-only "scan-and-serve" backend that makes a developer's manga folder appear in the app. Cloud sync / auth / URL import remain out of scope.
- Config: the library path lives only in a gitignored `.env` (`MANGA_LIBRARY_PATH`); never commit it.

Slices (each ships only after the prior one has an observable acceptance test):

- [x] **Slice 0 — contract + folder validation** (Coordinator, read-only). The real library matched the recorded format (3-level nesting, `NN-title` chapter dirs, zero-padded `.jpg` pages, one comic with `cover.jpg` and one relying on the fallback, `.DS_Store` present). No contract changes needed.
- [x] **Slice 1 — in-memory catalog API** (`backend-implementer`, new `backend/`; reviewed by `code-reviewer`). FastAPI scans `MANGA_LIBRARY_PATH` into memory; serves `GET /comics`, `GET /comics/{id}`; IDs are stable path hashes; read-only; no DB.
  - Verified: `/healthz` → 2 comics / 6 chapters; `curl` counts match disk; re-run byte-identical; IDs unchanged after the review fixes; 38 unit tests pass.
  - Review fixes applied: P2 symlink-escape guard (resolve + stay-under-root), P3 IDs derived from `relative_to(root)`. Deferred: `coverUrl` absolute shape + a dedicated cover route (Slice 2), the fail-fast-vs-503 cleanup, and counting non-page files at the comic/root level (minor).
- [x] **Slice 2 — page images + reader endpoint** (`backend-implementer`; reviewed by `code-reviewer`, no defects). `GET /comics/{id}/chapters/{cid}` returns ordered **absolute** page URLs (1-based index scheme); `GET /media/{comicId}/{chapterId}/{n}` and `GET /media/{comicId}/cover` stream image bytes; `coverUrl` is now absolute. URLs derive from `request.base_url` (host/port-agnostic).
  - Verified: 53 tests pass; page image `200 image/jpeg` byte-identical to disk `001.jpg`; cover `200 image/jpeg`; ordering matches disk; a `_safe_file` guard rejects every traversal/symlink escape (404, no leak); library read-only (fingerprint unchanged).
- [x] **Slice 3 — iOS consumes it** (`frontend-implementer`; reviewed by `code-reviewer`). `ComicRepository` protocol + `APIComicRepository` (URLSession/Codable); `HomeView`/`ChapterPageView`/`ComicView` repository-driven with loading/error states; a dedicated `ErrorStateView` with Retry; three `Image → AsyncImage` sites; `Models` retyped (`id: String`, `coverURL`/`pageURLs: URL`, `Decodable`); ATS for local HTTP; mock `PreviewComicRepository`/`SampleData` for previews.
  - Verified end-to-end on iPhone SE / iOS 18.1 against the live backend: library shows the real folder's comics with covers streamed from `/media`; backend-down shows the error page + Retry.
  - Review fixes applied: P2 cover clipping, P2 `LazyVStack` for reader pages, P3 lenient `readState` decode, P3 hide "Continue" when unavailable.
  - Follow-ups: base URL is now resolved from the `VISTA_BASE_URL` env var (set per Xcode scheme) with a compiled default of `127.0.0.1` — no machine-specific IP in tracked source; production HTTPS via xcconfig is deferred. Reader pages that fail to load now show a tap-to-retry placeholder (`AsyncImage` re-keyed to re-request just that page).
  - Residual (to confirm on-device): reader `LazyVStack` scroll + pull-past-bottom auto-advance and per-page retry on a real many-page chapter. Backlog: error-message granularity, URL-string decode tolerance, per-chapter thumbnail (no contract URL yet), production base-URL/ATS story.
- [x] **Slice 4 — reading-position persistence** (`backend-implementer` then `frontend-implementer`, sequential). Shipped across PRs #14–#17 (2026-07-23 – 2026-07-24).
  - **PostgreSQL** (not SQLite), via SQLAlchemy 2.0 + psycopg (sync); a single `progress` table `(comic_id, chapter_id)` → `last_page, page_count, updated_at`; `CREATE TABLE IF NOT EXISTS`, no Alembic.
  - **Docker Compose, two services** (`api` + `postgres`); manga folder read-only bind-mounted into `api`; `DATABASE_URL` in the gitignored `.env`. Redis was not needed.
  - **Page-level resume** shipped: `PUT /comics/{id}/chapters/{cid}/progress`; GET endpoints derive live `readState`/`lastReadAt`; reader response carries `lastReadPage`. iOS: reliable mid-chapter tracking via each page's `onAppear`/`onDisappear` (not the unreliable `.scrollPosition` readout on a lazy `AsyncImage` stack), debounced `saveProgress` writes, `.scrollPosition` resume. Progress-write failures are swallowed — a down store never interrupts reading.
  - `continueChapterId` added to `/comics`; the library's "Continue" button is always visible and opens that chapter directly via an id-based `ReaderRoute` (`ComicView` self-loads the comic detail).
  - Pull-past-bottom auto-advance restarts the next chapter at page 1 and overwrites its saved progress; explicit jumps still resume.
  - Library and chapter list silently refresh on return from the reader (no relaunch needed for "last read"/read badges to update).
  - Verified: device-tested on iPhone against the live backend — Continue targeting, mid-chapter resume, read-on-bottom, auto-advance restart, refresh-on-return, retry-all-failed-pages all confirmed by the developer.
  - Acceptance met: read to page K of a chapter, restart app/backend, resume at ~page K with the chapter shown as `reading`.

Load-bearing: server IDs must be stable across scans/restarts (path-derived hash), because Slice 4 keys progress on them.

Connectivity: a Cloudflare named Tunnel + Cloudflare Access (Service Token, not interactive login) now provides a stable public HTTPS endpoint (`api.vistabanana.com`) — `cloudflared` runs as a third Compose service routed only to `api` (never `postgres`); iOS attaches the Service Token headers via build-time `.xcconfig` → `Info.plist` config (survives launching the app standalone, unlike Xcode-scheme env vars). Shipped and verified end-to-end (PRs #19–#21, 2026-07-28); tracked as `.scratch/remote-access/`, not a separate `ROADMAP.md` slice, per the ticket-driven workflow those PRs established.

### M6 — OCR text selection + recognition

- Status: Complete (PR #25, #26; merged 2026-07-29)
- Owner: main session, implemented by `frontend-implementer`
- Dependencies: M5 (needs the live backend + real page images to select from)
- Spec of record: `.scratch/ocr-recognition/spec.md`; README roadmap item 3 ("OCR")
- Realizes README's long-range step: `Select a text region you don't understand → OCR recognition`

Tickets (all resolved):

- [x] **01 — Expose the decoded page image.** `AuthorizedAsyncImage` exposes the decoded source image via an `onDecoded` callback alongside the rendered `Image`, so a selection can crop the *original* pixels, not a screenshot of the scaled-down on-screen rendering.
- [x] **02 — Selection-to-crop coordinate mapping.** `SelectionCropMapping.cropRect`: a pure function mapping an on-screen selection rectangle to source-pixel space, correctly handling `.fit`-scale letterbox/pillarbox.
- [x] **03 — Reader selection-mode UI crops the live page image.** New selection mode in `ComicView` (doesn't disturb scroll/tap-to-toggle-controls); drag-to-select crops the live decoded page; a corner "drag here to cancel" zone aborts mid-drag with one continuous touch.
- [x] **04 — `OCRRecognizer` protocol + `VisionOCRRecognizer`.** Mirrors `ComicRepository`'s seam; `VisionOCRRecognizer` is v1's only implementation (on-device Vision, Vietnamese-only, fixed per the library's content), with three distinguishable error cases (`noTextFound`, `lowConfidence`, `underlying`).
- [x] **05 — Wire recognition into the selection flow.** Confirming a crop auto-recognizes it (`LoadState`-driven, reusing the project's existing async-fetch pattern); shows editable recognized text; distinct failure messages + retry/cancel per error case. Nothing is ever persisted (that's M8).
- [x] **06 — Join recognized lines into continuous text** (added 2026-07-30, requested during M8 manual testing). Vision returns one candidate per detected text *line*; `VisionOCRRecognizer.joinRecognizedLines` now joins consecutive lines with a space by default (continuing the same wrapped sentence), only keeping a hard newline where a line already ends in punctuation — fixes fragmented, line-by-line translation of wrapped dialogue.

Verification: 47/47 relevant unit/logic tests pass (tickets 01–05) + 5 new tests for ticket 06's joining logic, all green on a booted iOS 18.1 simulator; `xcodebuild build` succeeds. Explicitly unverified: `VisionOCRRecognizer`'s real-world Vietnamese-diacritic accuracy (`confidenceThreshold = 0.3` is an unmeasured placeholder) and a full manual selection→recognition walkthrough on-device — flagged for the developer to confirm before calling recognition quality production-ready.

### M7 — Tab bar navigation

- Status: Complete (PR #29; merged 2026-07-29)
- Owner: main session, implemented by `frontend-implementer`
- Dependencies: None (pure navigational restructuring)
- Spec of record: `.scratch/tab-bar-navigation/spec.md`
- Built ahead of M8 specifically because M8 needed an independent top-level screen ("單字本") to review saved learning material, which doesn't fit as a pushed screen off the library flow.

Tickets (all resolved):

- [x] **01 — Introduce tab bar navigation (書庫 + 單字本 placeholder).** `RootTabView` becomes the app's root (`vista_comicApp.swift`'s `WindowGroup` now hosts it instead of `HomeView` directly): 書庫 wraps the existing library/reader flow byte-for-byte unchanged; 單字本 is a new placeholder (`VocabularyView`, later populated by M8's ticket 06). `TabNavigationUITests` proves navigation-stack state survives a tab round-trip.

Verification: full-scheme build succeeds (confirmed independently after merge); `HomeView.swift`/`LibraryFlowUITests.swift`/`ReaderFlowUITests.swift` confirmed unmodified. Live UI-test execution could not be completed in the sandboxed CI-like environment that implemented this (structural accessibility-daemon limitation, not a code defect) — recommended for the developer to re-run on a working simulator/device session, which happened naturally once M8's manual testing began.

### M8 — OCR-to-translation: translate, save, and manage 單字本

- Status: Complete (PR [#31](https://github.com/towfd/vista_comic/pull/31); merged 2026-07-29)
- Owner: main session, implemented by `frontend-implementer`/`backend-implementer`
- Dependencies: M5 (backend), M6 (OCR result screen this attaches to), M7 (單字本 tab this populates)
- Spec of record: `.scratch/ocr-translation/spec.md`
- Realizes README's long-range steps: `Translation and meaning explanation → Save the word or sentence` (roadmap item 4) plus its own review surface

Tickets (all resolved):

- [x] **01 — `Translator` protocol + `AppleTranslator`.** Mirrors `OCRRecognizer`'s seam; wraps Apple's on-device `Translation` framework (bridged via `.translationTask` since there's no public `TranslationSession` initializer). Source is hard-coded Vietnamese (v1's only caller); target language is a parameter. **Real-device bug found and fixed**: originally bailed on *any* not-yet-installed language pack, including ones Apple could auto-prompt to download — now only genuinely `.unsupported` pairs bail early, letting `.supported` pairs reach the real call and trigger Apple's download-consent UI as designed.
- [x] **02 — Backend `saved_translation` table + save/list API.** `POST`/`GET /translations`, mirroring the `progress` table's pattern (`CREATE TABLE IF NOT EXISTS`, no migration tooling). 503-on-unavailable, not graceful degradation — there's no independent source of truth to fall back to, unlike the catalog.
- [x] **03 — `TranslationRepository` + `APITranslationRepository`.** iOS client mirroring `ComicRepository`'s shape; kept as its own domain seam (not bolted onto `ComicRepository`) since "saved learning material" is conceptually distinct from comic/reading-progress.
- [x] **04 — Translate button + language picker.** On the OCR result screen, on-device via `Translator`, defaulting to the last-used target language (Traditional Chinese first).
- [x] **05 — Save action.** Persists the original/translated pair + comic/chapter/page source reference to the backend; "Saved" confirmation replaces the button in place.
- [x] **06 — 單字本 tab shows the real saved-translation list**, replacing M7's placeholder — `LoadState`-driven loading/loaded/failed, each row showing original/translated text + comic/chapter/page/saved-at.
- [x] **07 — Jump from a saved translation back to its source page.** Each row's button opens the reader directly at the saved comic/chapter/page, as a **read-only preview** (`ReaderRoute.targetPage`/`isPeek` — new optional fields, existing call sites unaffected) that never calls `saveProgress`, so revisiting an old page can't regress real reading progress. 單字本 owns its own `NavigationStack`, independent of 書庫's.
- [x] **08 — Delete a saved translation.** Trash button per row, confirmed via a destructive `.alert` (irreversible, no undo). Backend `DELETE /translations/{id}` (204/404/503); iOS removes the entry from the displayed list in place on success.

**Two unrelated, pre-existing bugs found and fixed during this feature's manual verification:**
- The backend's ISO-8601 timestamps include fractional (microsecond) seconds (Python's `datetime.isoformat()`), which `JSONDecoder`'s stock `.iso8601` strategy can't parse — silently broke `Comic.lastReadAt` and `SavedTranslation.savedAt` decoding as soon as real (non-null) data existed, surfacing as a generic "Couldn't connect" on both 書庫 and 單字本. Fixed with a shared `APIConfig.iso8601Decoder`.
- (M6 follow-up, ticket 06 above) OCR line-fragmentation in translation output.

Verification: `xcodebuild build`/`test` clean (22/22 focused unit tests pass). Manual, against the real backend on booted iOS 18.1 simulators (iPhone SE, iPhone 16 Pro Max): full select → recognize → translate → save → 單字本 list → jump-to-source (peek mode) → delete round trip confirmed, including a real end-to-end delete verified against the live backend. Backend `pytest` for ticket 08 not runnable in the developer's local sandboxed environment (a native Postgres on the Mac shadows docker-compose's published port ahead of the test suite's connection — pre-existing, unrelated) — verified instead via direct curl against the real docker-composed endpoints. This sandboxed environment has no tap/drag-automation tool; interactive UI flows were verified by temporarily forcing navigation/state for a screenshot and reverting immediately after each time (confirmed clean via `git diff`).

### M9 — LLM-assisted comprehension

- Status: **Merged** — all 17 tickets resolved; PR [#35](https://github.com/towfd/vista_comic/pull/35) merged into `main` on 2026-08-04
- Owner: main session, implemented by `backend-implementer`/`frontend-implementer`
- Dependencies: M5 (backend), M8 (the OCR result screen's "Translate" action this extends, and the `saved_translation`/單字本 store this adds columns to)
- Spec of record: `.scratch/llm-comprehension/spec.md`; wayfinder map: `.scratch/llm-comprehension/map.md`
- Realizes the remainder of README roadmap item 4, explicitly deferred by M8's own spec: "Word/sentence/context explanations and any LLM-assisted comprehension"

M8 shipped a literal, on-device translation. A learner still can't see *why* a sentence translates the way it does — grammar structure, how the surrounding panel resolves an ambiguous pronoun, or tone/register. M9 extends the same select → OCR → translate flow with a cloud Claude call that returns translation + grammar notes + context notes + tone/register, keeping the on-device `Translator` as an automatic fallback rather than a hard failure.

Decision tickets (wayfinder map, all resolved) — destination/timing, model location, translation-merge/fallback design, structured-output/persistence shape, cost safety net, content-policy risk, daily-cap value, schema fields/model tier, result-screen UX, and the backend API contract. See `.scratch/llm-comprehension/map.md`'s Decisions-so-far for each.

Implementation tickets (all resolved):

- [x] **11 — Backend `POST /comprehend`: core contract.** Accepts a selection crop image, downscaled full-page image, source text, and target language; calls the Claude Messages API with a `strict: true` tool-use schema (`translation`, `grammarNotes`, `contextNotes`, `toneRegister`); a `status` field on HTTP 200 discriminates a genuine success from a model-declined outcome, so a decline is never confused with a connectivity/server error.
- [x] **12 — Backend cost guards.** A lenient per-request image-size ceiling (4xx) and a global daily request cap (300/day, a small `CREATE TABLE IF NOT EXISTS` Postgres counter) as anomaly guards against runaway cost — not real usage-limiting.
- [x] **13 — iOS `Comprehender` protocol + `APIComprehender`.** Mirrors `OCRRecognizer`/`Translator`'s seam; base64-encodes both images (page image downscaled to a ~1024px long edge in *pixel* space); `ComprehensionError` distinguishes `.declined` from `.underlying`.
- [x] **14 — Wire `Comprehender` into the Translate flow, with fallback + status banner.** The OCR result screen's "Translate" action now calls `Comprehender` first; a persistent capsule banner (☁️ blue "雲端深度解釋" / ⚠️ orange "內容政策・僅提供翻譯" / 📱 gray "離線模式・僅逐字翻譯") tells the reader at a glance which path a result came from, always shown before any content.
- [x] **15 — Persist explanation content.** `saved_translation` gains three nullable columns (`grammar_notes`, `context_notes`, `tone_register`); `POST`/`GET /translations` and the iOS "Save" action grow to carry them — a fallback-only save persists NULL, never an error.
- [x] **16 — 單字本 list shows saved explanation content.** `SavedTranslationRow` gains an expandable grammar/context/tone disclosure, shown only when a saved entry actually has explanation content; fallback-only and pre-existing (M8-era) rows render unchanged.
- [x] **17 — Manual "request a stronger explanation" action.** A secondary action on a successful (blue-banner) result re-calls `Comprehender` with the Sonnet-tier override, replacing the displayed result on success; absent entirely from the fallback states; a failed upgrade leaves the original result untouched.

**Deployment gap found and fixed during device-testing:** `docker-compose.yml`'s `api` service wasn't forwarding `ANTHROPIC_API_KEY` into the container (the repo-root `.env` is only used by Compose to interpolate `${...}` values, never copied into the container) — every real-device `/comprehend` call was silently 500ing and masked by the ticket 14 fallback, showing the gray "離線模式" banner even though nothing was actually offline. Fixed by forwarding the variable explicitly, the same way `DATABASE_URL` already was; verified live against the real container afterward.

Verification: `xcodebuild build`/`test` clean, full suite passing with no regressions; backend `pytest` (full suite) passing; build-verified on `iPhone SE (3rd generation)` and `iPhone 16 Pro Max`; `/code-review` (Standards + Spec axes) run per ticket, no hard violations. Live device test against the real backend (Claude Haiku 4.5) confirmed the blue-banner success path end-to-end. Interactive tap-through / XCUITest execution not run in this sandboxed environment (see Known issues and constraints) — left for the developer on a real device or normal Xcode session.

### M10 — Comprehension response UX

- Status: **Merged** — 12 wayfinder decisions resolved, spec written, all 10 implementation tickets (13–22) shipped; PRs [#38](https://github.com/towfd/vista_comic/pull/38)–[#48](https://github.com/towfd/vista_comic/pull/48) merged into `main` on 2026-08-06
- Owner: main session
- Spec of record: `.scratch/comprehension-response-ux/spec.md`; wayfinder map: `.scratch/comprehension-response-ux/map.md`

Reshapes M9's comprehension flow around the two complaints that surfaced from using it: the reader waits tens of seconds for anything at all, and the explanation comes back in an unpredictable language. The on-device translator is promoted from failure fallback to always-first, so a literal translation is immediate; the cloud explanation is enqueued on the **backend**, which owns it from then on and completes it across sheet dismissal, app backgrounding and container restarts. Every translate auto-creates a record — the manual Save is removed — and 單字本 becomes a **歷史紀錄** tab with an unread badge. The language problem is fixed at its root: the tool schema's three explanation fields now name the target language, verified against real Claude calls (18/18 note fields compliant on the default tier).

This deliberately **supersedes several of M9's own locked decisions** — the single merged call, the client-owned lifecycle, the manual save model, the one-shot verdict banner, the per-result stronger-model upgrade, and the "all note columns NULL means translation-only" convention. The spec's Further Notes carries the full list.

Also decided and deliberately deferred out of this milestone: adopting a migration tool (triggered by this schema landing), converting the backend to async (buys almost nothing at this scale), and history pagination/retention (no data yet on where the threshold is).

**Two things changed during implementation and are recorded as amendments in the spec rather than silently:**

- Ticket 19's "rows show the cloud translation" AC contradicted the mockup it was drawn from and was **superseded** in favour of two-line rows, since a third line costs roughly a third of the records visible on a list whose whole job is scanning. The intent survives in the row's status glyph, which is a cloud exactly when a cloud translation exists.
- The badge's refresh policy ("when the tab appears, no shared client store") was **reversed after shipping**, by ticket 22. A tab's content does not appear until the tab is selected, so the badge could only ever learn an explanation had arrived at the moment the reader opened the tab it existed to send them to — it contradicted its own user story. Ownership moved to the tab shell, which refreshes on launch/foreground and watches a record still in flight when the reader dismisses the result sheet.

`DROP TABLE saved_translation` was executed against the deployed database on 2026-08-06 as the last step of ticket 21, in the order `docs/manual-migrations.md` now records: merge the code that stops using the table, rebuild and confirm the API no longer serves the old routes, then drop. **Adopting a migration tool was therefore triggered** — the deferral was explicitly conditional on this landing — **and was done the next day** ([#55](https://github.com/towfd/vista_comic/pull/55), 2026-08-07).

### Alembic adoption (post-M10, ticket-driven)

- Status: **Merged** — PR [#55](https://github.com/towfd/vista_comic/pull/55) merged into `main` on 2026-08-07
- Owner: main session
- Spec of record: `.scratch/alembic-adoption/spec.md`

Closes the deferral M10 made conditional on its own schema landing. The backend had no migration tool: `db.init_engine` called `metadata.create_all` at startup, which can add a table but never a column — a limitation `docs/manual-migrations.md` existed to work around, by hand, per change.

Alembic now owns the schema. `create_all` is gone, the app runs `alembic upgrade head` itself on startup, and `docs/manual-migrations.md` is closed — kept only for the one-time stamp that connects the pre-Alembic database to the baseline revision, which is the step that makes the old era and the new one line up.

### Reader page prefetch (post-M10, ticket-driven)

- Status: **Merged** — tickets 01 and 02 shipped; PR [#60](https://github.com/towfd/vista_comic/pull/60) merged into `main` on 2026-08-09. Ticket 03 closed as **not doing**.
- Owner: main session
- Spec of record: `.scratch/reader-page-prefetch/spec.md`

Fixes reading being stop-start. Every Page used to begin loading only as it entered the viewport, so scrolling down was interrupted on *every* page; and because the lazy stack destroys off-screen rows, scrolling back up re-downloaded pages that had just been on screen, collapsing their height and lurching the scroll position. There was no cache anywhere in the image path.

Adds an in-memory Page image cache and a prefetch window — current Page, five ahead, two behind, seeded at the Page actually being displayed rather than at page one, four fetches at once in priority order, out-of-window requests cancelled, failed URLs marked so a dead network cannot become a request storm.

**The decisive detail was not the network round trip.** The request was issued from a task SwiftUI runs *after* the row has already been drawn once, so even a Page whose bytes were in hand still flashed its placeholder. Since reading an actor's state requires `await` and `await` cannot happen during body evaluation, the cache is deliberately two pieces — a synchronously readable store plus an actor owning what is in flight — so a hit is resolved during body evaluation and its first drawn frame already carries the image at full height. A second non-obvious find: `preparingForDisplay()` is best-effort and under load returns a non-nil image still backed by encoded data, leaving the decode on the main thread at draw time; decoding now goes through a `CGContext` this code constructs.

Sizing was measured against the real library rather than assumed — 1855 Pages, fixed widths (predominantly 900px), heights 8px–2500px, averaging 94 KB — which is why cost is treated as latency rather than bandwidth, why retention is bounded by decoded bytes (a proxy for reading distance, since width is fixed), and why five ahead was kept rather than ten (4.2 vs 8.3 median screens).

**Ticket 03 (reserving correct height for Pages not in memory) was closed as not doing**, after device verification: the synchronous hit path fixed the reported scroll-up jitter on its own, and the remaining first-pass shift was judged not noticeable. Spec user stories 8 and 9 are therefore unmet by design. Also rejected, with reasons recorded in the spec: backend-supplied Page dimensions, a disk cache, downsampling, and a hand-rolled LRU in place of `NSCache`.

## Known issues and constraints

- **CoreGraphics is being handed a NaN somewhere.** `Error: this application, or a library it uses, has passed an invalid numeric value (NaN...) to CoreGraphics API` appears in the console around the selection sheet, several times in a row. Almost certainly pre-existing — it predates the sheet-lifetime fix ([#50](https://github.com/towfd/vista_comic/pull/50)), which touched no geometry — and harmless so far, since CoreGraphics ignores the value. `SelectionCropMapping` and the selection-overlay drawing were both read and cleared. To find it, set `CG_NUMERICS_SHOW_BACKTRACE=1` in the scheme's environment variables and reproduce; the backtrace names the exact call site, which beats reading code for it.
- Xcode builds may report simulator-service or cache permission limitations in restricted execution environments.
- `LibraryFlowUITests` and `ReaderFlowUITests` now cover the core flow; the original unit/UITest boilerplate is still unused.
- Comic and chapter titles in `SampleData` are English placeholders (data, not UI chrome) and are intentionally not localized.
- The manga library path is machine-specific config kept only in a gitignored `.env` (`MANGA_LIBRARY_PATH`); it must never appear in committed files.
- This sandboxed development environment has no tap/drag-automation tool for interactive SwiftUI verification (confirmed structurally — an `XCUITest` accessibility-daemon timeout in M7, no windowed Simulator.app process available since — a recurring, not one-off, limitation). The workaround used since M8: temporarily force navigation/state for a screenshot, then revert before finishing, confirmed clean via `git diff` each time.
- The developer's Mac has a native Postgres process bound to `127.0.0.1:5432`, ahead of docker-compose's published port for the same address — backend `pytest` (which targets `localhost:5432`) cannot reach the docker-compose Postgres from this machine as a result. Verify backend endpoint changes by exercising the live `docker compose`-run `api` service directly (curl/rebuild-and-restart) instead, until this is resolved.

## Open decisions

- [x] First-release UI language: **Traditional Chinese (繁體中文)** (resolved 2026-07-21), delivered **localization-ready via a String Catalog — not hardcoded** (see Pending cross-cutting work). On-screen text only, not the SwiftUI framework.
- [x] User-facing section name: **Library** (resolved 2026-07-21) — renders as **書庫** under the Traditional Chinese UI. Keep internal filenames and types (`FavouriteView`, `FavouriteView.swift`, …) for now.

## Cross-cutting work

- [x] Localization-ready UI with Traditional Chinese — **no hardcoded Chinese** (done 2026-07-21). `Localizable.xcstrings` holds English development keys + 繁中 translations; `readStateLabel` / `lastReadText` use `String(localized:)`; `.accessibilityLabel` values are English keys; `zh-Hant` added to `knownRegions`. Follows the device language (English base, 繁中 first translation) — adding a language later is just a catalog column.
  - Verified: `BUILD SUCCEEDED`; launched with `-AppleLanguages (zh-Hant)` and confirmed 書庫 / 繼續閱讀 / 章節（N） / 尚未開始 / locale-formatted date render; `LibraryFlowUITests` + `ReaderFlowUITests` pass (forced English).

## Next action

M1–M10 are merged. The wayfinder map, spec and tickets for M10 live under `.scratch/comprehension-response-ux/`, which is the source of truth for their status, not this file.

The OCR text-editing defect — the last of the three problems reported alongside M10's two, split out at planning time as a `/diagnosing-bugs` effort — is **fixed** ([#50](https://github.com/towfd/vista_comic/pull/50)). It turned out not to be the lag it was reported as: the confirmation sheet was presented by a `ReaderPage`, a row inside the reader's `LazyVStack`, so the keyboard shrinking the scroll viewport recycled the owning row and destroyed the sheet's `@State` mid-correction. Rebuilding those rows re-decoded full-resolution pages on the main thread, which is where the stall came from — the keyboard was waiting on us, not the other way round. The sheet now belongs to `ReaderView`, which the lazy container cannot recycle.

**Nothing is in progress. The next action is unclaimed**, in rough order of how much each is already owed:

- ~~**Adopt a migration tool.**~~ — **done, 2026-08-07** ([#55](https://github.com/towfd/vista_comic/pull/55)). Alembic owns the schema; `docs/manual-migrations.md` is closed and kept only for the one-time stamp that connects the two eras. This bullet outlived the work by two days and was still being read as owed on 2026-08-09.
- ~~**Whole-book precompute**~~ — **abandoned, 2026-08-07.** Precomputing OCR + LLM over a whole comic at import, so no selection is needed at read time, was carried as the long-term direction through M9 and M10. It is now dropped: the select-and-translate flow stays as the model.

  This is the decision's third and final pass. M9's wayfinder considered a batch pipeline and rejected it as replacing the selection design rather than extending it; M10 deferred it again to ship a usable version of the current model first. That version shipped, has been used, and is what the reader wants.

  **The consequence worth noting is what it removes, not what it cancels.** The selection flow was described in both efforts as a first usable version of something later replaced, which quietly put a shelf life on any investment in it. There is no shelf life now: Dynamic Type, the reader-screen structure surfaced by [#50](https://github.com/towfd/vista_comic/pull/50), and history retention are all improvements to the permanent model.
- **History pagination or retention.** Less pressing since translate and 深入解釋 split (2026-08-08): only an explicit explanation request writes a row now, so rows accrue at the rate the reader asks for explanations rather than at the rate they glance at speech bubbles. Still deferred until there are real row counts rather than a guess.
- **Backend async conversion.** Deferred until real usage shows the backend being held up, with numbers.

Longer range, README roadmap item 5 ("Profile and sync") remains the only major direction not yet covered by a milestone.

Backlog (unstarted): Dynamic Type support (move off fixed font sizes); dark-appearance colour variants; README §2 URL import; `LibraryFlowUITests`/`ReaderFlowUITests` still assert `"Frieren"`, which doesn't match the real backend's actual seeded library (`marrymyhusband`/`marrymyhusband2`) — noted during M7, not yet fixed.
