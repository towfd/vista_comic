# 05 — Wire recognition into the selection flow, editable and non-persisted

**What to build:** completing a selection (Ticket 03) calls the recognizer (Ticket 04) and replaces the crop-preview with the recognized text, shown editable so the user can correct misreads. Dismissing discards the content — nothing is ever written to any store, local or backend. No-text-found, low-confidence, and Vision-level errors surface a clear message with a way to retry the selection or cancel, never a silent failure. This is the ticket where the feature works end-to-end.

**Blocked by:** 03, 04

**Status:** resolved (commit `0e62140` on `feat/ocr-recognition-foundation`)

- [x] Completing a selection calls `OCRRecognizer` and shows the recognized text in an editable field/sheet — recognizer call verified by running (unit tests); the SwiftUI `.task`/`TextEditor` wiring verified by inspection only
- [x] Editing and dismissing the result discards it — no write to any store, local or backend — inspection only: `.sheet(item:)` gives each selection a fresh view instance, and no persistence call exists anywhere in the new code
- [x] No text found / low confidence / Vision-level errors show a visible message with an option to retry the selection or cancel — no silent failure — all three `OCRRecognitionError` cases verified by running to surface as `.failed`; message copy and button behavior verified by inspection only
- [x] Unit tests exercise the full flow via a stub `OCRRecognizer` (selection-complete → recognize → display/edit) — **verified by running**: 7/7 tests pass (`SelectionRecognitionFlowTests`), including a no-`cgImage` boundary case
- [ ] Manual verification: drawing a selection over real Vietnamese dialogue in the actual library produces a reasonable recognition result, and the correction flow works end-to-end — **not done**; no live backend or real device/simulator interaction session was available in any of this feature's implementation sessions

## Comments

Last ticket in `.scratch/ocr-recognition/` — the full pipeline (select → crop → recognize → edit → discard) is now wired and merged into `feat/ocr-recognition-foundation`. Final integration run: 47/47 relevant tests pass (including all 7 new ones here); 3 unrelated UI-test failures, all simulator/environment infrastructure (2 pre-existing backend-dependent failures, 1 new simulator-boot-timeout on `testLaunchPerformance` — not a performance regression).

**Open item, not blocking:** `VisionOCRRecognizer.confidenceThreshold = 0.3` remains an unmeasured placeholder. No session across all five tickets had a live backend or real device to validate actual Vietnamese-diacritic recognition accuracy against the developer's real library. Worth a manual pass before treating this feature as production-ready, and worth revisiting whether `APIOCRRecognizer` (out of scope for this feature, per spec.md) is actually needed once that's known.
