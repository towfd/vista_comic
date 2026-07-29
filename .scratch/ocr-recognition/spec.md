Status: ready-for-agent

# OCR text selection and recognition

## Problem Statement

While reading in `vista_comic`, the user hits dialogue text they don't understand — the library is Vietnamese-subtitled scanlations of Korean webtoons, all Latin-script text with diacritics. Today the Reader only renders Pages as images; there is no way to pull a piece of on-page text out as recognizable, editable plain text. The user has to leave the app entirely (or just not understand) to make sense of a line of dialogue.

## Solution

Add a text-selection mode to the existing continuous-scroll Reader (`ComicView.swift`). The user draws a rectangle over the Page region they want recognized; the app crops that region out of the Page's original decoded image (not a screenshot of the scaled-down on-screen rendering), sends the crop through a swappable `OCRRecognizer` interface, and shows the recognized text on screen as editable so the user can fix misreads. Nothing is persisted — the result exists only for the current viewing session. v1 recognizes Vietnamese only, via iOS's on-device Vision framework (`VisionOCRRecognizer`); the interface is designed so a future backend-hosted recognizer can be swapped in without touching the selection/crop/display flow.

## User Stories

1. As a reader, I want to select a piece of on-page text I don't understand, so that I can see it as recognized plain text without leaving the Reader.
2. As a reader, I want to draw a rectangle over just the dialogue bubble I care about, so that surrounding artwork isn't sent to OCR and doesn't hurt recognition accuracy.
3. As a reader, I want the selection gesture to not conflict with the Reader's existing scroll and tap-to-toggle-controls gestures, so that I don't accidentally trigger a selection while scrolling or hide/show controls while selecting.
4. As a reader, I want an explicit way to enter and exit selection mode, so that the Reader's normal reading gestures are unaffected when I'm not trying to select text.
5. As a reader, I want to see the recognized text shown clearly after I finish a selection, so that I can read it immediately.
6. As a reader, I want to edit the recognized text if OCR got it wrong, so that I still get the correct content even when recognition makes a mistake.
7. As a reader, I want to cancel a selection before it's sent for recognition, so that a misdrawn rectangle doesn't force an unwanted recognition round-trip.
8. As a reader, I want to dismiss a recognition result and keep reading, so that nothing about trying OCR leaves any trace once I move on.
9. As a reader without network connectivity, I want text recognition to keep working, so that using the app off Wi-Fi/cellular doesn't break word lookup.
10. As a reader, I want a clear message when recognition fails (no text found, low confidence, a Vision error) instead of a silent hang, so that I understand a bad selection or unreadable crop didn't just do nothing.
11. As a reader, I want recognition of a small, tightly-drawn selection to still use good image quality, so that Vietnamese diacritics aren't lost to a low-resolution crop.
12. As the developer, I want OCR execution to go through a swappable `OCRRecognizer` protocol, so that replacing on-device Vision with a backend-hosted recognizer later is an implementation swap, not a redesign of the selection/crop/display flow.
13. As the developer, I want the screen-selection-to-source-pixel-crop mapping to be a pure, non-view unit, so that its correctness is verifiable with fast unit tests rather than only manual/UI testing.
14. As the developer, I want the Reader's image-loading path to expose the original decoded image alongside the SwiftUI `Image` it renders, so that crops are taken from full-resolution source pixels.
15. As the developer, I want the `OCRRecognizer` protocol to not hard-code a language, so that adding a language beyond Vietnamese later doesn't require a protocol redesign.
16. As the developer, I want this feature to introduce no backend API or schema changes, so that it stays a pure iOS-side increment matching its current scope.

## Implementation Decisions

- **New protocol `OCRRecognizer`** (`Networking/`, alongside `ComicRepository`, following the same seam pattern: screens/logic depend on the protocol, not a concrete recognizer). Shape: an async method taking a source image (or already-cropped `CGImage`) and returning recognized text; exact signature and whether it returns richer output than a bare `String` (e.g. confidence) is left to implementation, not locked here.
- **v1's only concrete implementation: `VisionOCRRecognizer`**, wrapping `VNRecognizeTextRequest` / `VNImageRequestHandler`, configured for Vietnamese recognition. Exact `recognitionLanguages` code and achievable accuracy are being verified separately (open research question, see Further Notes) and don't block this implementation — the protocol boundary means the concrete recognizer can be revisited without redesigning the feature.
- **Execution location and language are not hard-coded into the protocol.** A future `APIOCRRecognizer` (calling a backend-hosted model) is a drop-in replacement for `VisionOCRRecognizer`, not a runtime dual-path/fallback inside the app. Out of scope here (see below).
- **Crop source: original decoded image, not an on-screen screenshot.** The Reader's image-loading path (`AuthorizedAsyncImage` or its call site in `ReaderPage`) needs to expose the decoded `UIImage`/`CGImage` it already has in its `.success` phase, not just the SwiftUI `Image` value, so crops come from full-resolution source pixels.
- **Selection-to-crop coordinate mapping is a pure, non-view unit** — input: the on-screen selection rectangle plus the displayed image's frame/scale metadata; output: the crop rectangle in source-image pixel space. This is the primary unit-testable seam alongside the protocol itself.
- **Reader gains an explicit selection mode**, entered/exited via a control (following the existing `controlsOverlay` button pattern), distinct from the current tap-to-toggle-controls gesture, so drawing a rectangle doesn't collide with scrolling or the controls toggle.
- **Recognition result display is transient and editable**: an overlay or sheet shown after a selection completes, containing an editable text field pre-filled with the recognized text; dismissing it discards the content. No write to any store, local or backend.
- **Failure handling**: no-text-found, low-confidence, and Vision-level errors all surface a visible message in the same result UI, with a way to retry the selection or cancel — no silent failure.
- **No backend changes**: no new API endpoint, no new database table/column. This is a pure iOS-side increment.

## Testing Decisions

- Tests exercise external behavior — given a selection and a stubbed `OCRRecognizer`, the flow calls the recognizer once with the correctly-cropped input and renders/updates the editable result — not SwiftUI rendering internals.
- **`OCRRecognizer` boundary**: unit tests using a stub implementation (same shape as the stubbed `URLProtocol`-backed test added for `APIComicRepository` in the `remote-access` ticket — the project's first Networking-layer unit test). Assert the selection → recognize → display/edit path without invoking real Vision.
- **Selection-to-crop mapping**: unit tests over the pure mapping function/type — a table of (selection rect, image display metadata) → expected crop rect, including boundary cases (selection partially outside the image bounds, selection spanning into an adjacent Page).
- **`VisionOCRRecognizer` accuracy is not automated** — real-image OCR quality isn't something a fast unit test can meaningfully assert. Verified manually: draw a selection over real Vietnamese dialogue in the actual library, confirm the recognized text is reasonable and the correction flow works.
- Prior art: `APIComicRepository`'s stubbed-`URLProtocol` request test (`remote-access`); `LibraryFlowUITests` / `ReaderFlowUITests` for end-to-end flow coverage, extendable if the selection gesture's end-to-end behavior later needs a UI test (not required for this spec).

## Out of Scope

- Automatic dialogue-bubble boundary detection — manual rectangle selection only. May resurface later if manual selection proves too fiddly in practice.
- `APIOCRRecognizer` (a backend-hosted recognizer) — its API contract and backend model choice are undesigned; only worth specifying if `VisionOCRRecognizer`'s measured accuracy on Vietnamese turns out insufficient.
- Recognition languages other than Vietnamese — the protocol doesn't hard-code language, but no other language is implemented here.
- Persisting recognized/corrected text anywhere (local or backend), including any "select words to save" vocabulary mechanism — deferred to a future milestone, and explicitly to be revisited once LLM-assisted word/phrase handling is in the picture.
- Translation or meaning explanation of recognized text.
- Any hand-off interface to a future translation feature — since nothing here persists, there's nothing to hand off yet; that shape gets decided when that milestone starts.
- Any backend API or schema change.

## Further Notes

- This spec was converged through a `/wayfinder`-style discussion with the developer rather than a written map — the architectural principles below (protocol-based execution location, manual-only selection, Vietnamese-first scope, no persistence) were each confirmed individually in that conversation.
- The developer's actual manga library (`marrymyhusband`, `marrymyhusband2`) is Vietnamese-subtitled Korean webtoon scanlations — Latin script with diacritics, not CJK vertical text — which is why v1 targets Vietnamese specifically rather than a general multi-language CJK-capable pipeline.
- One fact-finding question remains open and is being pursued separately: how well Apple's Vision framework actually recognizes Vietnamese diacritics in practice. It doesn't block this spec (v1 ships with `VisionOCRRecognizer` regardless), but its result should inform whether/when `APIOCRRecognizer` gets specified.
- A separate, unrelated thread from this same discussion: the developer is planning to move the Docker Compose backend to a dedicated always-on machine, which would be the natural host for a future `APIOCRRecognizer` backend model if one is ever built. No dependency on this spec.
