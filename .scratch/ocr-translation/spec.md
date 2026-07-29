Status: ready-for-agent

# OCR-to-translation: translate and save recognized text

## Problem Statement

After OCR recognition (the `ocr-recognition` feature) shows the user editable, recognized Vietnamese text, they have no way to understand what it means or keep it for later — the result screen is dismiss-only and nothing persists. The user wants to translate the corrected text into a language they read, and save the original/translation pair somewhere they can come back to.

## Solution

Add a "Translate" action to the OCR result screen (`CroppedSelectionPreview`, from `ocr-recognition` ticket 05). Tapping it translates the corrected text using Apple's on-device `Translation` framework (Vietnamese source; target language user-selectable, defaulting to the last-used language or Traditional Chinese on first use), shows original and translated text side by side, and offers a "Save" action that persists the pair to the backend. Saved pairs are listed in the "單字本" tab (built by the `tab-bar-navigation` spec; this spec fills it with real content).

## User Stories

1. As a reader, after correcting OCR-recognized text, I want to tap "Translate" to see it in a language I understand, so I don't have to leave the app to look it up.
2. As a reader, I want the translation to default to Traditional Chinese, so most of the time I don't have to pick a language at all.
3. As a reader, I want to change the target language for a specific translation if I want a different one, so I'm not locked into always translating to the same language.
4. As a reader, once I've changed the target language, I want that choice remembered as the new default, so I don't have to re-pick it every time.
5. As a reader, I want to see the original Vietnamese text and the translation side by side, so I can compare them directly.
6. As a reader, I want to save a translation I care about, so I can find it again later without re-reading the same page.
7. As a reader, I want saved translations to show up in the "單字本" tab, so I have one place to review everything I've saved.
8. As a reader, I want each saved entry to show enough context (which comic/chapter/page it came from, when I saved it) so I can find my way back to the source if I want to.
9. As a reader, I want translation to work without needing a network connection beyond what's already required to load manga pages, so on-device translation doesn't introduce a new failure mode.
10. As a reader, I want a clear message if translation fails (e.g. the on-device language model isn't downloaded yet), so I'm not left staring at nothing.
11. As the developer, I want translation execution behind a swappable protocol, so swapping the on-device framework for a different provider later doesn't require redesigning this feature.
12. As the developer, I want the backend save/list operations behind their own seam, separate from `ComicRepository`, so "saved learning material" stays a distinct domain concept, not bolted onto the comic/reading-progress domain.
13. As the developer, I want no changes to the `ocr-recognition` feature's existing files beyond adding the "Translate" entry point, so this spec stays additive to already-shipped, reviewed work.

## Implementation Decisions

- **`Translator` protocol** (`Networking/`, mirrors `OCRRecognizer`'s seam): an async method taking text plus a target language, returning translated text, throwing on failure (e.g. the on-device language pack isn't installed/downloaded, translation unavailable). Source language is not a parameter — v1's only caller is the OCR flow, which only ever produces Vietnamese text (per `ocr-recognition`'s language-scope decision); the source is hard-coded in the concrete implementation, not the protocol, mirroring how `VisionOCRRecognizer` hard-codes Vietnamese only in itself.
- **`AppleTranslator`** (or similar name): v1's only implementation, wrapping the `Translation` framework — confirmed to support Vietnamese and Traditional Chinese (verified via Apple Developer documentation and WWDC24's "Meet the Translation API" during the `/wayfinder` discussion this spec came from). Note for the implementer: Apple's Translation API is SwiftUI-integrated via `.translationTask(_:action:)` rather than a plain freestanding async function — the concrete implementation needs to work within that shape while still presenting a clean `Translator`-conforming async interface to callers. Exact plumbing is an implementation detail, not locked here.
- **Target-language selection**: a small picker in the OCR result screen, defaulting to the last-used target language, persisted locally (e.g. `UserDefaults` — a lightweight per-device setting, not learning material, so it doesn't need backend storage). First-ever default is Traditional Chinese.
- **New `TranslationRepository` protocol** (or similar name, `Networking/`, mirrors `ComicRepository`'s shape): methods to save a translation pair and to list saved pairs, backed by a new `APITranslationRepository` calling new backend endpoints.
- **Backend**: new Postgres table (e.g. `saved_translation`) — columns for original text, translated text, target language, source comic/chapter/page reference, and a timestamp. New endpoints: one to save, one to list. Follows the existing `progress` table's precedent (a single new table, `CREATE TABLE IF NOT EXISTS`, no migration tooling, per `docs/adr/0004-docker-compose-topology.md`) — no Redis, no auth beyond what already gates the API (Cloudflare Access, per ADR-0005), same single-user assumption as the rest of the backend.
- **The "單字本" tab** (placeholder from `tab-bar-navigation`) is replaced with a real list view driven by `TranslationRepository`'s list method, following the existing `LoadState`-driven loading/loaded/failed pattern used throughout the app.
- **The "Translate" action** lives in `CroppedSelectionPreview` (from `ocr-recognition`), added as a new button alongside its existing editable-text/dismiss UI — additive, not a restructuring of that view.
- No changes to `OCRRecognizer`, `VisionOCRRecognizer`, or any other `ocr-recognition` file.
- Backend save is unconditional on how translation executes (on-device here) — decided during `/wayfinder` independent of the on-device-vs-backend translation question, since progress-tracking already has backend infrastructure and cross-device review access is valuable regardless.

## Testing Decisions

- Good tests exercise the `Translator` and `TranslationRepository` protocol boundaries with stubs, not real on-device translation or real network calls — mirrors `OCRRecognizerTests`'/`APIComicRepositoryTests`'s existing stub patterns.
- Unit tests: a stub `Translator` proves the translate-button flow calls it correctly and handles success/failure; a stub `TranslationRepository` proves save and list wiring.
- Backend: new tests for the save/list endpoints, following `backend/tests/`'s existing conventions for the `progress` endpoint.
- `AppleTranslator`'s real on-device translation quality is not automated (mirrors `VisionOCRRecognizer`'s stance on real Vietnamese OCR accuracy) — verified manually.
- Manual verification (required, environment permitting): translate real OCR'd Vietnamese text end-to-end, confirm a saved entry appears in "單字本" after an app relaunch (proving backend persistence, not just local state).

## Out of Scope

- Word/sentence/context explanations and any LLM-assisted comprehension — explicitly deferred to a separate future `/wayfinder` effort, per the milestone-4 decomposition discussion.
- Word-level selection/segmentation for saving individual vocabulary — same deferral (depends on the LLM work).
- Any translation entry point other than the OCR result screen (e.g. free-text input, translating from the saved-list screen itself).
- Editing or deleting a saved translation once saved.
- Any language pair other than Vietnamese-source (target is user-selectable, but the app never offers a non-Vietnamese source, since OCR itself is Vietnamese-only).
- Cross-device sync beyond "stored on the backend" — no account system, no conflict resolution; same single-developer, single-device-at-a-time assumption the rest of the backend already carries.

## Further Notes

- Blocked by the `tab-bar-navigation` spec — needs the "單字本" tab to exist before this spec can populate it.
- Decided via `/wayfinder`: on-device translation via Apple's `Translation` framework was chosen over a backend translation API after research confirmed Vietnamese support, avoiding a new dockerized translation service. If on-device quality proves insufficient, a future `Translator` implementation calling a backend service remains a drop-in swap, per the protocol's design.
- Word/sentence-explanation and LLM-comprehension (README's other milestone-4 sub-items) are intentionally not covered here — flagged as their own future `/wayfinder` effort, given their complexity (LLM provider choice, prompt design, cost control).
