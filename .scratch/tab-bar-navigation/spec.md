Status: ready-for-agent

# Tab bar navigation foundation

## Problem Statement

The app currently has no tab-based navigation — everything lives under a single `NavigationStack` rooted at `HomeView` (the library/書庫 screen). Upcoming milestone-4 work (translating OCR-recognized text and saving the results) needs a new, independent top-level screen to review saved learning material, which doesn't fit naturally as a pushed screen off the library flow. Retrofitting tab navigation later, once more screens and tests exist, would cost more than doing it now while the app is small.

## Solution

Introduce a `TabView` as the app's root navigation shell, with two tabs: "書庫" (wrapping the existing `HomeView`/library/reader flow, unchanged in behavior) and "單字本" (a new, empty placeholder screen for now, populated by a later feature). This is a pure navigational restructuring — no new user-facing functionality beyond the second tab existing and being reachable.

## User Stories

1. As a user, I want to see a tab bar with "書庫" and "單字本" tabs, so that I know there's a dedicated place for saved learning material even before it has content.
2. As a user, I want the "書庫" tab to behave exactly as the app does today (browse comics, read chapters, resume progress), so that this restructuring doesn't regress anything I already rely on.
3. As a user, I want switching tabs and back to preserve each tab's state (scroll position, loaded data), so the tabs feel like independent, persistent areas rather than resetting each time.
4. As a user opening "單字本" for the first time, I want a clear placeholder, not a blank screen or a crash, so I understand this tab exists and is intentionally empty for now.
5. As the developer, I want the existing UI test suite (`LibraryFlowUITests`, `ReaderFlowUITests`) to keep passing, so I have concrete proof this restructuring didn't regress the current app.
6. As the developer, I want a new UI test exercising tab switching, so the two-tab structure itself is covered, not just the content within each tab.
7. As the developer, I want the "單字本" tab to be trivially extensible later (swap one placeholder view for a real one), so a future feature can slot its content in without touching the tab-bar scaffolding again.

## Implementation Decisions

- New root view (e.g. `RootTabView`) hosting a `TabView` with two tab entries: "書庫" (wraps the existing `HomeView()` unchanged) and "單字本" (wraps a new, minimal placeholder view, e.g. `LearningRecordView`, using an empty-state pattern consistent with `FavouriteView`'s existing `ContentUnavailableView` usage).
- `vista_comicApp.swift`'s `WindowGroup` instantiates `RootTabView()` instead of `HomeView()` directly. The `comicRepository` environment injection stays at this top level, since `HomeView` (now nested inside the "書庫" tab) still depends on it.
- `HomeView` itself is not modified — its `NavigationStack`, load logic, and navigation destinations stay exactly as they are; it becomes one tab's content, not the app's root.
- Tab icons: SF Symbols, following the existing icon-based pattern used elsewhere in the app (e.g. `books.vertical`, matching `FavouriteView`'s empty-state icon, for 書庫; a book/text-related symbol for 單字本 — exact icon choice left to implementation, not load-bearing).
- No new persistence, no new backend calls, no new business logic — purely a view-hierarchy change.
- Localization: both tab labels go through the existing `Localizable.xcstrings` convention (English development keys + 繁中 translations), matching how "Library"/"書庫" is already handled.

## Testing Decisions

- Good tests here assert on navigational reachability and preserved behavior, not on how `TabView` happens to be wired internally.
- `LibraryFlowUITests` and `ReaderFlowUITests` must keep passing (with only the minimal changes needed to locate elements now nested one level deeper under a tab, if the accessibility hierarchy requires it) — this is the primary regression check for this spec.
- New UI test: switching to "單字本" shows the placeholder; switching back to "書庫" shows the library exactly as before. SwiftUI's `TabView` preserves each tab's view identity by default when switching, so no special state-preservation code should be needed — the test should confirm this holds, not assume it.
- No unit tests expected — this spec introduces no pure logic to test in isolation.
- Prior art: `LibraryFlowUITests`/`ReaderFlowUITests` themselves, for UI-test structure and conventions.

## Out of Scope

- Any real content in the "單字本" tab — that's a separate, later feature (the OCR-to-translation spec), blocked by this one.
- Any change to `HomeView`'s internal behavior, the reader, or the backend.
- More than two tabs, or any tab-reordering/customization UI.
- Persisting which tab was last selected across app launches (always opens to "書庫").

## Further Notes

- This spec exists specifically to unblock the upcoming OCR-to-translation feature spec, which needs a dedicated screen to show saved translations. Decided via `/wayfinder`: introducing tab navigation now, while the app has few screens, is cheaper than retrofitting it later.
- The "單字本" name is provisional (could also read "學習紀錄") — the content-bearing spec that fills this tab may finalize the label.
