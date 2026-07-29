# 05 — Wire recognition into the selection flow, editable and non-persisted

**What to build:** completing a selection (Ticket 03) calls the recognizer (Ticket 04) and replaces the crop-preview with the recognized text, shown editable so the user can correct misreads. Dismissing discards the content — nothing is ever written to any store, local or backend. No-text-found, low-confidence, and Vision-level errors surface a clear message with a way to retry the selection or cancel, never a silent failure. This is the ticket where the feature works end-to-end.

**Blocked by:** 03, 04

**Status:** ready-for-agent

- [ ] Completing a selection calls `OCRRecognizer` and shows the recognized text in an editable field/sheet
- [ ] Editing and dismissing the result discards it — no write to any store, local or backend
- [ ] No text found / low confidence / Vision-level errors show a visible message with an option to retry the selection or cancel — no silent failure
- [ ] Unit tests exercise the full flow via a stub `OCRRecognizer` (selection-complete → recognize → display/edit), independent of real Vision
- [ ] Manual verification: drawing a selection over real Vietnamese dialogue in the actual library produces a reasonable recognition result, and the correction flow works end-to-end
