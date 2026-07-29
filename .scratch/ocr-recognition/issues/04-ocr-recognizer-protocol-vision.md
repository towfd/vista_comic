# 04 — `OCRRecognizer` protocol + `VisionOCRRecognizer`

**What to build:** the recognition engine in isolation, with no Reader/UI wiring. An `OCRRecognizer` protocol (in `Networking/`, matching the seam shape of `ComicRepository`) takes an image and returns recognized text (or a richer result type, left to implementation), with distinguishable error cases. `VisionOCRRecognizer` is the only v1 implementation, wrapping `VNRecognizeTextRequest`/`VNImageRequestHandler` configured for Vietnamese recognition. The protocol itself must not hard-code language or execution location, so a future backend-hosted recognizer can be a drop-in replacement later.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] `OCRRecognizer` protocol defined in `Networking/`, shaped so screens/logic depend on the protocol, not a concrete recognizer
- [ ] `VisionOCRRecognizer` implements it via `VNRecognizeTextRequest`/`VNImageRequestHandler`, recognition language fixed to Vietnamese
- [ ] No text found, low confidence, and Vision-level failures are represented as distinguishable outcomes the caller can branch on and message from
- [ ] Unit tests exercise the protocol boundary (a stub/double conforming to `OCRRecognizer`) and `VisionOCRRecognizer`'s plumbing (image in, text/error out) — real-world Vietnamese recognition accuracy is not asserted by these tests
