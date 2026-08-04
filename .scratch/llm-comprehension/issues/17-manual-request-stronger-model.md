# 17 — Manual "request a stronger explanation" action

**What to build:** a secondary action on the result screen (exact placement/wording left to the implementer, per the spec) that re-issues the `Comprehender` call with the Sonnet-tier override (already supported by ticket 13's `APIComprehender` and ticket 11's backend contract), replacing the currently-shown result with the new one once it returns. Only meaningful after a successful (blue-banner) result — a fallback state has no "explanation" to upgrade. Demoable by translating, then tapping the upgrade action, and observing the result refresh with (typically) a deeper explanation.

**Blocked by:** 14

**Status:** resolved

- [x] A secondary action is available once a successful (blue-banner) comprehension result is showing
- [x] Tapping it re-calls `Comprehender` with the Sonnet-tier override and replaces the displayed result on success
- [x] The action is not shown (or is disabled) in the fallback (gray/orange banner) states, since there's no explanation to upgrade
- [x] A failure on the upgraded call leaves the original (Haiku-tier) result visible rather than clearing it — the reader never ends up with less than they had before tapping upgrade
- [x] Unit tests exercise this action with a stub `Comprehender`, covering both a successful upgrade and a failed upgrade attempt

## Comments

Implemented on `feat/llm-comprehension-foundation`. Changed only `Features/ComicPage/ComicView.swift` (`CroppedSelectionPreview` gains an `upgradeButton`, rendered only inside the `.comprehended` branch alongside the grammar/context/tone columns — genuinely absent from the view tree in the fallback states, not merely disabled) plus a new free function `upgradeComprehension`, kept deliberately separate from ticket 14's `comprehendOrTranslateSelection` since the two have incompatible failure semantics: the existing function falls back to `Translator` on any failure, this one must never fall back and must leave `translationState` completely untouched on failure (verified by tracing every write to `translationState` — only the `.loaded` branch of `upgrade()`'s switch touches it).

Upgrade-in-flight/failure state uses a separate `isUpgrading: Bool` + `upgradeError: String?` pair rather than folding into a `LoadState`, deliberately mirroring `VocabularyView.deleteError`/`SavedTranslationRow.isDeleting`'s existing precedent for "an in-place action that must not disturb the surrounding displayed content" — the established convention in this codebase for this exact shape of requirement, as opposed to `translationState`/`saveState`'s `LoadState` convention (used where an action fully replaces what's displayed).

New tests in `vista_comicTests/SelectionComprehensionFlowTests.swift` (4 tests): `useStrongerModel: true` is actually sent, a successful upgrade yields the new result, a failed upgrade (both `.declined` and `.underlying`) surfaces as `.failed` without any fallback call.

Verified: `xcodebuild build` succeeds; `xcodebuild test -only-testing:vista_comicTests` — 103+ tests pass (4 new + all pre-existing), no regressions. Build-verified on `iPhone SE (3rd generation)` (compact) and `iPhone 16 Pro Max` (larger).

Code review (`/code-review`): Spec axis found zero issues across all 5 AC lines. Standards axis flagged one judgement call (the `isUpgrading`/`upgradeError` shape vs. `LoadState`) — not actioned, since closer inspection showed it's a deliberate mirror of the `deleteError`/`isDeleting` precedent already established elsewhere in this codebase for the same kind of requirement, not a new smell.

This resolves the last open ticket in the `llm-comprehension` feature — all 17 tickets are now `resolved`.
