# 06 — 單字本 tab shows the real saved-translation list

**What to build:** the 單字本 tab's placeholder (from `tab-bar-navigation`'s Ticket 01) is replaced with a real list view driven by `TranslationRepository`'s list method (Ticket 03), following the existing `LoadState`-driven loading/loaded/failed pattern used throughout the app. Each entry shows enough context (original text, translation, source comic/chapter/page, saved-at time) to be useful for review.

**Blocked by:** 03 (this feature), and `tab-bar-navigation`'s **01 — Introduce tab bar navigation (書庫 + 單字本 placeholder)** (`.scratch/tab-bar-navigation/issues/01-introduce-tab-bar.md`) — the 單字本 tab must exist before this ticket can populate it

**Status:** resolved

- [x] 單字本 tab fetches and shows all saved translations via `TranslationRepository`, replacing the placeholder
- [x] Loading, loaded, and failed states are all handled (matching `LoadState`'s established usage elsewhere in the app)
- [x] Each entry shows original text, translated text, and enough source context (comic/chapter/page, saved-at time) to identify where it came from
- [x] Manual verification: confirmed against the real backend on booted iOS 18.1 simulators (iPhone SE — compact, iPhone 16 Pro Max — larger) — both saved entries from Ticket 05's testing appear correctly

## Comments

Implementation is `VocabularyView.swift` + new `Features/Vocabulary/components/SavedTranslationRow.swift`.

**A real, pre-existing, unrelated bug was found and fixed during this ticket's manual verification**: the 單字本 list failed to decode with the generic "Couldn't connect" error on real backend data. Root cause — the backend emits ISO-8601 timestamps with fractional (microsecond) seconds (Python's `datetime.isoformat()`, e.g. `2026-07-29T22:20:10.081902+00:00`), but `JSONDecoder`'s stock `.iso8601` strategy's `ISO8601DateFormatter` doesn't accept fractional seconds and throws — silently breaking `savedAt` decoding (and, identically, `Comic.lastReadAt` in `APIComicRepository`, which is why 書庫 was *also* broken against real data with reading history). Fixed with a shared `APIConfig.iso8601Decoder` (tries fractional-seconds format, falls back to plain) now used by both `APIComicRepository` and `APITranslationRepository`. This had nothing to do with ticket 05/06's own logic — it only ever surfaced once real (non-null, non-exactly-on-the-second) timestamps existed in the data, which prior manual verification attempts (blocked by this same sandboxed environment's simulator limitations, per `tab-bar-navigation` ticket 01's comments) hadn't reached.
