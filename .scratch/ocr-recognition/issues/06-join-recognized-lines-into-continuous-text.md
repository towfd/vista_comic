# 06 — Join Vision's per-line results into continuous text instead of hard newlines

**What to build:** `VisionOCRRecognizer.recognizeText` currently joins Vision's per-observation candidates with `"\n"` (one hard line break per detected text line). For wrapped dialogue — a single sentence spanning multiple lines in a speech bubble — this reads as fragmented, and translating it produces a broken, line-by-line translation instead of one continuous sentence. Join with a space by default (continuing the same sentence/clause); only keep a line break where a line already ends in punctuation (a real clause/sentence boundary), not on every wrapped line.

**Blocked by:** None — isolated change to `VisionOCRRecognizer`'s output joining, no protocol/contract change

**Status:** resolved

- [x] Joining logic extracted into `VisionOCRRecognizer.joinRecognizedLines(_:)`, an `internal static func` (default access, no `private`) so `@testable import vista_comic` can exercise it directly
- [x] Consecutive lines join with a single space when the prior line does NOT end in punctuation
- [x] A line ending in punctuation (`. , ! ? : ; …`) keeps a newline break before the next line
- [x] Empty/whitespace-only lines are skipped (trimmed + filtered before joining)
- [x] Unit tests added to `VisionOCRRecognizerTests.swift`: no-punctuation join, punctuation-terminated newline, single line passthrough, empty/whitespace-only lines skipped, mixed punctuated/unpunctuated — 5/5 pass
- [x] Existing real-Vision tests (`recognizesTextDrawnIntoASyntheticImage`, `throwsNoTextFoundForABlankImage`) still pass — confirmed via `xcodebuild test` on a booted iOS 18.1 simulator (iPhone SE)

## Comments

Requested by the user (2026-07-30) while testing `ocr-translation` PR31: multi-line OCR results were translating "斷斷續續" (fragmented/discontinuous) because each wrapped line was translated as if it were its own sentence. This ticket only changes `VisionOCRRecognizer`'s internal joining — `OCRRecognizer`'s protocol contract (`recognizeText(in:) -> String`) is unchanged, so nothing downstream (`Translator`, `TranslationRepository`, the OCR result screen) needs to change.

**Not manually verified end-to-end against a real page's text-selection → OCR → translate flow**: this sandboxed environment has no tap/drag-automation tool (same limitation as `tab-bar-navigation` ticket 01), so the selection-drag gesture that triggers real OCR recognition can't be driven here. Confidence instead comes from: the pure `joinRecognizedLines` unit tests covering the exact behaviors requested, and the unmodified real-Vision recognition test still passing (proves the surrounding plumbing — confidence thresholding, error paths — is untouched). Recommend the user manually confirm on-device that wrapped dialogue now reads as one continuous translated sentence.
