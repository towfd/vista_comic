# 13 — iOS `Comprehender` protocol + `APIComprehender`

**What to build:** a new `Comprehender` protocol (mirroring `OCRRecognizer`/`Translator`'s existing shape) and its sole implementation, `APIComprehender`, which calls the real `POST /comprehend` backend endpoint (ticket 11). Takes the selection crop image, the full page image, the source text as currently shown on screen, and a target language; returns a structured result or throws an error distinguishing at least a declined outcome from an underlying/network one. This ticket delivers the protocol and its real implementation only — not wired into any screen yet (that's ticket 14).

**Blocked by:** 11

**Status:** ready-for-agent

- [ ] `Comprehender` protocol defined in `Networking/`, with an async method taking crop image, page image, source text, and target language, returning a structured result (`translation`, `grammarNotes`, `contextNotes`, `toneRegister`) or throwing
- [ ] A `ComprehensionError` (or similarly named) type distinguishes at least "declined" from "underlying failure," mirroring `OCRRecognitionError`'s/`TranslationError`'s existing pattern of distinguishable cases
- [ ] `APIComprehender` calls the real backend endpoint, correctly base64-encodes both images, and correctly maps the backend's `status` field / HTTP errors onto the protocol's success/error cases
- [ ] `APIComprehender` supports requesting the Sonnet-tier override (wired end-to-end by ticket 17, but the parameter exists on this protocol/implementation now)
- [ ] Unit tests exercise `APIComprehender` against a stubbed network layer (mirroring `APIComicRepositoryTests`'/`APITranslationRepositoryTests`'s existing pattern) — no real network call in the test suite
