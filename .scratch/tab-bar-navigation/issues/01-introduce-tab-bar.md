# 01 — Introduce tab bar navigation (書庫 + 單字本 placeholder)

**What to build:** the app launches into a `TabView` with two tabs — 書庫 (wraps the existing `HomeView`/library/reader flow exactly as it works today) and 單字本 (a new, empty placeholder screen). This is a pure navigational restructuring: no new business logic, no new persistence, nothing in 單字本 yet beyond a clear "nothing here yet" state.

**Blocked by:** None — can start immediately

**Status:** resolved (commits `977e08b`, `e5efafc` on `feat/tab-bar-navigation`)

- [x] App launches with a visible tab bar showing 書庫 and 單字本(named `VocabularyView`/"Vocabulary" in code, reconciled with `ocr-translation` ticket 06's terminology — see Comments)
- [x] 書庫 tab shows the existing library, unchanged — `HomeView.swift` is byte-for-byte untouched (confirmed via `git diff`); `LibraryFlowUITests`/`ReaderFlowUITests` were not modified. **Not verified by a passing run** — see Comments, this is an environment limitation
- [x] 單字本 tab shows a clear placeholder (not blank, not a crash) — code-reasoned correct, not visually confirmed (same limitation)
- [x] Switching between tabs preserves each tab's state — `TabNavigationUITests` asserts navigation-stack preservation (a pushed chapter list survives a tab round-trip); scroll-position preservation is reasoned to follow from the same `TabView` mechanism rather than separately tested (see the test file's header comment — the real library's 2 comics fit on screen without scrolling, so a swipe assertion would be a no-op)
- [x] A new UI test covers reaching both tabs — `TabNavigationUITests.swift`, written and build-verified, **not run to a pass** (see Comments)

## Comments

**Verification status — full-scheme build succeeds** (confirmed independently by the coordinator after merge, isolated `-derivedDataPath`). **Live UI-test execution could not be completed**: multiple attempts (by the implementing agent and the coordinator separately, including after `xcrun simctl shutdown all` to rule out cross-agent contention) all failed with the same infrastructure error — `The test runner failed to initialize for UI testing. (Underlying Error: Timed out waiting for AX loaded notification)` — even running alone on a freshly-cleared simulator. This is a structural limitation of this sandboxed environment's accessibility daemon for XCUITest specifically, not a code defect or resource contention. Confirmed via: `HomeView.swift` unmodified, `LibraryFlowUITests`/`ReaderFlowUITests` unmodified (byte-for-byte), full build succeeds, and the new test's logic reads correctly against real backend data.

**Found and fixed during code review** (not part of the original implementation): the agent's first draft named the placeholder `LearningRecordView`, which didn't match `ocr-translation`'s ticket 06 (already written, calls this the "vocabulary tab"/`TranslationRepository`) — renamed to `VocabularyView` before this cost a shotgun-surgery rename later. Also found the new test asserted `"Frieren"` (copy-pasted from `LibraryFlowUITests`, which itself asserts data that doesn't match the real backend's actual current library — `marrymyhusband`/`marrymyhusband2`) — fixed in the new test; **`LibraryFlowUITests.swift`/`ReaderFlowUITests.swift` themselves still assert `"Frieren"` and were left untouched, per this ticket's scope, but this is a pre-existing, separate defect worth the developer's attention independent of this ticket.**

**Recommended before considering this fully done**: re-run `LibraryFlowUITests`, `ReaderFlowUITests`, and `TabNavigationUITests` on a working simulator session (e.g. locally in Xcode, or once this sandboxed environment's AX daemon issue is resolved) to get real pass/fail evidence and a visual check on compact + larger iPhone layouts, per CLAUDE.md's verification checklist.
