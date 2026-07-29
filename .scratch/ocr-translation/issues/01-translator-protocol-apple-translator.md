# 01 — `Translator` protocol + `AppleTranslator`

**What to build:** the translation engine in isolation, with no UI wiring. A `Translator` protocol (in `Networking/`, matching the seam shape of `OCRRecognizer`/`ComicRepository`) takes text and a target language, returns translated text, and throws on failure (e.g. the on-device language pack isn't installed). `AppleTranslator` is v1's only implementation, wrapping Apple's `Translation` framework, with the source language hard-coded to Vietnamese in the implementation only — not the protocol.

**Blocked by:** None — can start immediately

**Status:** resolved (commit `0d6d11b`, fixed further in `2d21b59`, on `feat/ocr-translation-foundation`)

- [x] `Translator` protocol defined in `Networking/`, shaped so screens/logic depend on the protocol, not a concrete translator
- [x] `AppleTranslator` implements it via the `Translation` framework; source language is Vietnamese only (hard-coded in this conformer, not the protocol), target language is a parameter
- [x] Failure to translate (e.g. language pack unavailable) is represented as a distinguishable outcome the caller can message from, not a bare generic error
- [x] Unit tests exercise the protocol boundary (a stub/double conforming to `Translator`) and `AppleTranslator`'s plumbing — **verified by running** (build-for-testing + protocol-boundary unit tests); real on-device translation itself is unverifiable in Simulator (see Comments)

## Comments

**SDK shape confirmed directly from the installed SDK's `.swiftinterface`, not secondhand docs**: `TranslationSession` has no public initializer at all — the only documented way to obtain one is SwiftUI's `.translationTask(_:action:)` modifier. `AppleTranslator` bridges this into a plain `async throws -> String` by momentarily hosting an invisible view carrying `.translationTask` in the app's key window, resuming a `CheckedContinuation` once the session responds.

**Apple's `Translation` framework does not function in the iOS Simulator — device only.** Unlike `VisionOCRRecognizer` (which could run real Vision in Simulator for `ocr-recognition`), no real translation was ever executed by any agent or the coordinator in this environment. Verification here is build success + `build-for-testing` (compiles the test bundle without paying Simulator's ~120s test-runner-launch tax) + protocol-boundary stub tests.

**Real-device bug found and fixed after merge** (commit `2d21b59`): the original implementation bailed out with our own `.languagePackUnavailable` error whenever `LanguageAvailability.Status != .installed`, which included `.supported` (downloadable, just not downloaded yet) — this meant the real `.translationTask` call, which is what triggers Apple's own automatic download-consent UI, never ran. The user saw only our fallback "go to Settings" text with no actual way to trigger a download from the app. Fixed: only `.unsupported` (genuinely never available) bails early now; `.supported` falls through to the real call, letting the system's own download prompt appear. Confirmed via `LanguageAvailability.Status`'s actual three cases read from the SDK interface (`.installed`/`.supported`/`.unsupported`). Not yet re-confirmed on a real device after the fix — worth a follow-up check.
