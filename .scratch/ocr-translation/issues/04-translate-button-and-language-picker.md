# 04 — OCR result screen gains a "Translate" button + language picker

**What to build:** in the OCR result screen (`CroppedSelectionPreview`, from `ocr-recognition`), add a "Translate" action that calls `Translator` (Ticket 01) on the corrected recognized text and shows the original and translated text side by side. A language picker lets the user pick the target language for this translation, defaulting to the last-used target language (persisted locally, e.g. `UserDefaults`), or Traditional Chinese on first use. No saving yet — this ticket is demoable purely as "translation appears on screen."

**Blocked by:** 01

**Status:** resolved (commit `16a9116` on `feat/ocr-translation-foundation`)

- [x] A "Translate" button appears in the OCR result screen alongside the existing editable recognized text
- [x] Tapping it calls `Translator` with the current (possibly user-corrected) text and selected target language, showing a loading state while it runs — recognizer call and state transitions verified by running (`SelectionTranslationFlowTests`); the SwiftUI button/picker wiring itself is build-verified only, per CLAUDE.md's UI-verification policy
- [x] Original and translated text are shown side by side once translation succeeds (implemented as an `HStack` with a `Divider()` — not simulator-verified visually)
- [x] A language picker is available (curated list: Traditional Chinese, English, Japanese, Korean, French, Spanish — not exhaustive, Traditional Chinese first/default), defaulting to the last-used target language via `UserDefaults`; changing it updates the persisted default
- [x] Translation failure shows a clear message distinguishing `.languagePackUnavailable` from `.underlying` — no silent failure
- [x] Unit tests exercise this flow via a stub `Translator` — **verified by running**: 11/11 tests pass (`SelectionTranslationFlowTests` + `TranslatorTests`), independent of the real `Translation` framework

## Comments

Translation state (`translationState: LoadState<String>?`) kept deliberately separate from `recognitionState` — recognition runs automatically on appear, translation runs on demand and shouldn't be conflated with a different lifecycle. `translateSelection(_:to:using:)` extracted as a free function (sibling to `recognizeSelection`), same reasoning as everywhere else in this file: keeps the logic testable without SwiftUI rendering.

Persisted the picker's `id` string directly (e.g. `"zh-Hant"`) rather than deriving one from `Locale.Language` — avoided depending on uncertain `Locale.Language` string-accessor behavior. This turned out to simplify Ticket 05 too, since `TranslationRepository.save`'s `targetLanguage: String` parameter could just reuse the same string with no conversion.

New user-facing strings ("Translate", "Translate to", "Original", "Translation", etc.) were not registered in `Localizable.xcstrings` inside this ticket's own file boundary — left for a coordinator follow-up commit, matching how `ocr-recognition`'s equivalent strings were handled (`4c23969`).
