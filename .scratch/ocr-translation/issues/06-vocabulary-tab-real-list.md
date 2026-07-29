# 06 — 單字本 tab shows the real saved-translation list

**What to build:** the 單字本 tab's placeholder (from `tab-bar-navigation`'s Ticket 01) is replaced with a real list view driven by `TranslationRepository`'s list method (Ticket 03), following the existing `LoadState`-driven loading/loaded/failed pattern used throughout the app. Each entry shows enough context (original text, translation, source comic/chapter/page, saved-at time) to be useful for review.

**Blocked by:** 03 (this feature), and `tab-bar-navigation`'s **01 — Introduce tab bar navigation (書庫 + 單字本 placeholder)** (`.scratch/tab-bar-navigation/issues/01-introduce-tab-bar.md`) — the 單字本 tab must exist before this ticket can populate it

**Status:** ready-for-agent

- [ ] 單字本 tab fetches and shows all saved translations via `TranslationRepository`, replacing the placeholder
- [ ] Loading, loaded, and failed states are all handled (matching `LoadState`'s established usage elsewhere in the app)
- [ ] Each entry shows original text, translated text, and enough source context (comic/chapter/page, saved-at time) to identify where it came from
- [ ] Manual verification (environment permitting): after Ticket 05 saves an entry, relaunch the app and confirm it still appears in 單字本 — proving this reads from the backend, not local-only state
