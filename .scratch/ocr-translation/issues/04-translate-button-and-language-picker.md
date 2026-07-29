# 04 — OCR result screen gains a "Translate" button + language picker

**What to build:** in the OCR result screen (`CroppedSelectionPreview`, from `ocr-recognition`), add a "Translate" action that calls `Translator` (Ticket 01) on the corrected recognized text and shows the original and translated text side by side. A language picker lets the user pick the target language for this translation, defaulting to the last-used target language (persisted locally, e.g. `UserDefaults`), or Traditional Chinese on first use. No saving yet — this ticket is demoable purely as "translation appears on screen."

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] A "Translate" button appears in the OCR result screen alongside the existing editable recognized text
- [ ] Tapping it calls `Translator` with the current text and selected target language, showing a loading state while it runs
- [ ] Original and translated text are shown side by side once translation succeeds
- [ ] A language picker is available, defaulting to the last-used target language (or Traditional Chinese if none set yet); changing it updates the persisted default
- [ ] Translation failure (e.g. language pack unavailable) shows a clear message, not a silent failure
- [ ] Unit tests exercise this flow via a stub `Translator`, independent of the real `Translation` framework
