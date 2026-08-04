# 13 — iOS `Comprehender` protocol + `APIComprehender`

**What to build:** a new `Comprehender` protocol (mirroring `OCRRecognizer`/`Translator`'s existing shape) and its sole implementation, `APIComprehender`, which calls the real `POST /comprehend` backend endpoint (ticket 11). Takes the selection crop image, the full page image, the source text as currently shown on screen, and a target language; returns a structured result or throws an error distinguishing at least a declined outcome from an underlying/network one. This ticket delivers the protocol and its real implementation only — not wired into any screen yet (that's ticket 14).

**Blocked by:** 11

**Status:** resolved

- [x] `Comprehender` protocol defined in `Networking/`, with an async method taking crop image, page image, source text, and target language, returning a structured result (`translation`, `grammarNotes`, `contextNotes`, `toneRegister`) or throwing
- [x] `ComprehensionError` distinguishes `.declined` from `.underlying(String)`, mirroring `OCRRecognitionError`'s/`TranslationError`'s existing pattern
- [x] `APIComprehender` calls the real backend endpoint, correctly base64-encodes both images (the page image downscaled to a ~1024px long edge in pixel space, not point space, before encoding — see the file's `downscaled(_:maxDimension:)` doc comment for why point-space would silently over-send on Retina sources), and correctly maps the backend's `status` field / HTTP errors onto the protocol's success/error cases
- [x] `APIComprehender` supports requesting the Sonnet-tier override (`useStrongerModel` parameter exists now; no UI calls it yet, per scope)
- [x] Unit tests exercise `APIComprehender` against a stubbed `URLProtocol` network layer, mirroring `APITranslationRepositoryTests`'s existing convention — no real network call in the test suite

## Comments

Implemented by `frontend-implementer` on `feat/llm-comprehension-foundation`, in parallel with ticket 12. New: `Networking/Comprehender.swift`, `Networking/APIComprehender.swift`, `vista_comicTests/APIComprehenderTests.swift` (11 tests).

`ComprehenderKey`'s `EnvironmentKey` default (`APIComprehender()`, network-backed) deliberately follows `TranslationRepositoryKey`'s precedent, not `TranslatorKey`'s/`OCRRecognizerKey`'s on-device-safe-default one — there is no `PreviewComprehender` and none was required by this ticket; a `#Preview`/canvas that doesn't override the environment value simply never calls `comprehend(...)`, since it only runs from an explicit user action (ticket 14).

Verified independently: `xcodebuild build` succeeds; `xcodebuild test -only-testing:vista_comicTests` — 81/81 pass (11 new + 70 pre-existing), exit code 0, no regressions.

Code review (`/code-review`, run jointly with ticket 12) found no hard violations and confirmed the `EnvironmentKey`-precedent claim and error-enum naming both check out against the codebase. No changes requested.
