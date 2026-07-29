# 01 — `Translator` protocol + `AppleTranslator`

**What to build:** the translation engine in isolation, with no UI wiring. A `Translator` protocol (in `Networking/`, matching the seam shape of `OCRRecognizer`/`ComicRepository`) takes text and a target language, returns translated text, and throws on failure (e.g. the on-device language pack isn't installed). `AppleTranslator` is v1's only implementation, wrapping Apple's `Translation` framework, with the source language hard-coded to Vietnamese in the implementation only — not the protocol.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] `Translator` protocol defined in `Networking/`, shaped so screens/logic depend on the protocol, not a concrete translator
- [ ] `AppleTranslator` implements it via the `Translation` framework; source language is Vietnamese only (hard-coded in this conformer, not the protocol), target language is a parameter
- [ ] Failure to translate (e.g. language pack unavailable) is represented as a distinguishable outcome the caller can message from, not a bare generic error
- [ ] Unit tests exercise the protocol boundary (a stub/double conforming to `Translator`) and `AppleTranslator`'s plumbing (text + target language in, translated text/error out) — real-world translation quality is not asserted by these tests
