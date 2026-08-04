# 14 — Wire `Comprehender` into the Translate flow, with fallback + status banner

**What to build:** the end-to-end reader-facing behavior this whole feature is for. `CroppedSelectionPreview`'s existing "Translate" action now calls `Comprehender` (ticket 13) first. On success, the result screen shows the four comprehension fields under a blue "雲端深度解釋" banner. On a declined outcome or any thrown error, it automatically falls back to the existing `Translator` call (unchanged) and shows a translation-only result under a distinct banner — orange "內容政策・僅提供翻譯" for declined, gray "離線模式・僅逐字翻譯" for any other error. No changes to `Translator`, `AppleTranslator`, `OCRRecognizer`, or `VisionOCRRecognizer`'s own behavior. This is the first ticket a reader can actually experience end-to-end on a device.

**Blocked by:** 13

**Status:** resolved

- [x] Tapping "Translate" calls `Comprehender` first, not `Translator` directly
- [x] On success, all four fields (translation, grammar notes, context notes, tone register) render under a blue "雲端深度解釋" banner, always shown before any content
- [x] On a declined outcome, the flow falls back to calling `Translator` and shows the resulting translation under an orange "內容政策・僅提供翻譯" banner
- [x] On any other `Comprehender` failure (network, backend error), the flow falls back to calling `Translator` and shows the resulting translation under a gray "離線模式・僅逐字翻譯" banner
- [x] The exact text sent to `Comprehender`/`Translator` is whatever is currently shown in the editable recognized-text field (the user's correction, if any) — never re-derived from the image
- [x] The existing "Save" action, language picker, and jump-back-to-source behavior are all unaffected by this change (verified by the existing `SelectionTranslationFlowTests`-style tests still passing unmodified, or updated only where the call site genuinely changed)
- [x] Unit tests exercise this flow with a stub `Comprehender` covering all three outcomes (success, declined, error), mirroring the existing `SelectionTranslationFlowTests` pattern
- [x] Build-verified on both a compact and a larger simulator layout (interactive tap-through left to the developer, per this project's documented environment limitation)

## Comments

Implemented on `feat/llm-comprehension-foundation`. Changed only `Features/ComicPage/ComicView.swift` (`ReaderPage` now reads `\.comprehender` and threads the full page image through `CroppedSelection`/`CroppedSelectionPreview`; `CroppedSelectionPreview`'s "Translate" action now calls a new free function, `comprehendOrTranslateSelection`, which tries `Comprehender` first and falls back to the unchanged `translateSelection`/`Translator` path on `.declined` or any other thrown error). New `SelectionTranslateOutcome` enum (`comprehended`/`translatedOnly(reason:)`) replaces the old bare `LoadState<String>` translation state so the view has one state to switch on instead of two nullable results. New test file `vista_comicTests/SelectionComprehensionFlowTests.swift` (12 tests) adds a `StubComprehender` mirroring `StubTranslator`, covering success (no fallback call), declined fallback, other-error fallback, the fallback-translator-itself-failing case, and the two distinct reasons never colliding.

Verified: `xcodebuild build` succeeds; `xcodebuild test -only-testing:vista_comicTests` — all tests pass (12 new + all pre-existing), exit code 0, no regressions to `SelectionTranslationFlowTests`/`SelectionSaveFlowTests`/`SelectionRecognitionFlowTests`. Build-verified on both `iPhone SE (3rd generation)` (compact) and `iPhone 16 Pro Max` (larger) simulator destinations. Interactive tap-through and XCUITest execution left to the developer per this project's documented XCUITest/simulator limitation.

Code review (`/code-review`, Standards + Spec axes run in parallel): no hard violations on either axis. Standards axis flagged one judgement-call-only smell (mild Repeated Switches on `outcome` between the banner helper and the inline `.comprehended` check for extra columns) — not actioned, since the two switches serve genuinely different purposes (banner text vs. optional extra content) and splitting further would add indirection without a real duplication to remove.
