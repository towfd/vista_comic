# 01 — Introduce tab bar navigation (書庫 + 單字本 placeholder)

**What to build:** the app launches into a `TabView` with two tabs — 書庫 (wraps the existing `HomeView`/library/reader flow exactly as it works today) and 單字本 (a new, empty placeholder screen). This is a pure navigational restructuring: no new business logic, no new persistence, nothing in 單字本 yet beyond a clear "nothing here yet" state.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] App launches with a visible tab bar showing 書庫 and 單字本
- [ ] 書庫 tab shows the existing library, unchanged — `LibraryFlowUITests` and `ReaderFlowUITests` pass without modification (or only trivial locator changes if tab-wrapping requires it)
- [ ] 單字本 tab shows a clear placeholder (not blank, not a crash)
- [ ] Switching between tabs preserves each tab's state (SwiftUI's default `TabView` behavior — verify this holds, don't just assume it)
- [ ] A new UI test covers reaching both tabs
