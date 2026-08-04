# 14 — Wire `Comprehender` into the Translate flow, with fallback + status banner

**What to build:** the end-to-end reader-facing behavior this whole feature is for. `CroppedSelectionPreview`'s existing "Translate" action now calls `Comprehender` (ticket 13) first. On success, the result screen shows the four comprehension fields under a blue "雲端深度解釋" banner. On a declined outcome or any thrown error, it automatically falls back to the existing `Translator` call (unchanged) and shows a translation-only result under a distinct banner — orange "內容政策・僅提供翻譯" for declined, gray "離線模式・僅逐字翻譯" for any other error. No changes to `Translator`, `AppleTranslator`, `OCRRecognizer`, or `VisionOCRRecognizer`'s own behavior. This is the first ticket a reader can actually experience end-to-end on a device.

**Blocked by:** 13

**Status:** ready-for-agent

- [ ] Tapping "Translate" calls `Comprehender` first, not `Translator` directly
- [ ] On success, all four fields (translation, grammar notes, context notes, tone register) render under a blue "雲端深度解釋" banner, always shown before any content
- [ ] On a declined outcome, the flow falls back to calling `Translator` and shows the resulting translation under an orange "內容政策・僅提供翻譯" banner
- [ ] On any other `Comprehender` failure (network, backend error), the flow falls back to calling `Translator` and shows the resulting translation under a gray "離線模式・僅逐字翻譯" banner
- [ ] The exact text sent to `Comprehender`/`Translator` is whatever is currently shown in the editable recognized-text field (the user's correction, if any) — never re-derived from the image
- [ ] The existing "Save" action, language picker, and jump-back-to-source behavior are all unaffected by this change (verified by the existing `SelectionTranslationFlowTests`-style tests still passing unmodified, or updated only where the call site genuinely changed)
- [ ] Unit tests exercise this flow with a stub `Comprehender` covering all three outcomes (success, declined, error), mirroring the existing `SelectionTranslationFlowTests` pattern
- [ ] Build-verified on both a compact and a larger simulator layout (interactive tap-through left to the developer, per this project's documented environment limitation)
