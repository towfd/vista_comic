# 16 — 單字本 list shows saved explanation content

**What to build:** extend the 單字本 list (`SavedTranslationRow` and related views) so a saved entry with explanation content (ticket 15) can be expanded to show its grammar/context/tone notes, while a fallback-only entry (those fields NULL) renders exactly as it does today — no broken or confusingly empty explanation section. No changes to the existing "jump back to source" (peek) behavior. Demoable by opening 單字本 and expanding both a full and a fallback-only saved entry.

**Blocked by:** 15

**Status:** resolved

- [x] A 單字本 row with non-NULL explanation fields can be expanded to reveal grammar/context/tone notes
- [x] A 單字本 row with NULL explanation fields (a fallback-only save, or a pre-existing M8-era saved translation) renders unchanged from today — no broken UI, no visible empty section implying missing data
- [x] The existing "jump back to source" (peek) action is unaffected
- [x] Build-verified on both a compact and a larger simulator layout for both row states (full and fallback-only)

## Comments

Implemented on `feat/llm-comprehension-foundation`, alongside ticket 15 in the same pass (this ticket's list depends on ticket 15's `SavedTranslation.grammarNotes`/`contextNotes`/`toneRegister`).

`SavedTranslation.hasExplanation` (new computed property, `Networking/SavedTranslation.swift`) gates a new `explanationDisclosure` chevron + grammar/context/tone section in `SavedTranslationRow` — only rendered at all when `hasExplanation` is true, so a fallback-only or pre-existing row's layout is byte-for-byte what it was before this ticket (no reserved space, no chevron, no empty section). `VocabularyView`'s "Loaded" preview and `SavedTranslationRow`'s own preview both now show a fallback-only row alongside a full-explanation one, for visual comparison. The "jump to source" `NavigationLink`/delete flow are untouched.

New `vista_comicTests/SavedTranslationTests.swift` (4 tests) exercises `hasExplanation` as pure logic: all-nil, all-present, partially-present (defensive — the fields are expected to always be saved together, but the property doesn't assume that), and decoding a response that omits the keys entirely.

Verified: `xcodebuild build` succeeds; `xcodebuild test -only-testing:vista_comicTests` all pass, no regressions. Build-verified on `iPhone SE (3rd generation)` (compact) and `iPhone 16 Pro Max` (larger), both showing the fallback-only and full-explanation preview states. Interactive tap-through (actually tapping the disclosure chevron) left to the developer per this project's documented XCUITest/simulator limitation.

Code review (`/code-review`, run jointly with ticket 15): no hard violations. See ticket 15's Comments for the two minor judgement calls noted (neither specific to this ticket's own row-expansion code).
