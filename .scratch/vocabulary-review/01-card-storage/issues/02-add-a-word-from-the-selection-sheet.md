# 02 — Add a word from the selection sheet

**What to build:** The reader corrects the OCR, taps Translate, and a button beside the result puts that line in their vocabulary. One tap, without leaving the page they are reading.

This is the first ticket a reader can see, and the first time a selection leaves anything behind without spending a request on a deep explanation.

**The card keeps whatever translation was on screen when the button was tapped.** `CroppedSelectionPreview.swift:332` renders `record?.displayedTranslation ?? translation`, so the cloud wording replaces the on-device one as soon as it arrives — which means what gets stored depends on whether the reader waited for an explanation. That is the intent, not an accident: the stored translation is the one they read and judged correct. Nothing upgrades it afterwards.

**There is no remove.** Stage 1 ships without a management screen, by decision. Collected is a static state.

`CroppedSelectionPreview.swift:66` currently says `editedText` is "purely for on-screen display/correction — never written anywhere". That stops being true here and must be replaced with what is now true.

**Blocked by:** 01.

**Status:** implemented on branch `feat/learning-card-store`, 2026-08-19 — `BUILD SUCCEEDED`, `TEST SUCCEEDED` on the whole `vista_comicTests` target, 9 new tests passing. **Device-verified by the repo owner, 2026-08-19, with one item outstanding** — see *What the device pass actually established*.

- [x] The button appears only under a loaded translation, and is disabled when the corrected text trims to empty
- [x] Tapping it creates a card carrying the corrected source text, the translation currently displayed, the target language, and comic / chapter / page
- [x] When the cloud translation has already replaced the on-device one on screen, that is what the card stores
- [x] The button shows idle, in-flight and collected; collected offers no removal
- [x] Adding a line that already exists leaves exactly one card and still shows collected
- [x] A failed add says so and leaves the button usable
- [x] Reading is not interrupted: the button never blocks the sheet or the page behind it
- [x] `LearningCard` is `Decodable`-only, and the repository is injected through an `EnvironmentKey` matching `comprehensionRepository`
- [x] The `editedText` comment no longer claims the text is never written anywhere
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `Networking/LearningCard.swift` — `Decodable`-only, matching `LearningCardResponse` 1:1.
- `Networking/StudyRepository.swift` — the seam plus its `EnvironmentKey`, mirroring `ComprehensionRepository`. Named for what the resource is *for*, so the reviewing stages add sessions and results to it rather than growing a second seam beside it.
- `Networking/APIStudyRepository.swift` — the live conformer, routed through `APIConfig.authorizedRequest` like every other call.
- `SelectionActions.swift` — `collectSelection(...)` and `CollectionOutcome`, a free function for the same reason `requestExplanation` is one: testable against a stub with no SwiftUI in the way.
- `CroppedSelectionPreview.swift` — the button, its four states, and the `editedText` comment rewritten.
- `ComicView.swift` — reads `studyRepository` from the environment and passes it down, the same two lines `comprehensionRepository` already occupied.

No change to `vista_comicApp.swift`: the `EnvironmentKey` default is the live conformer, which is the precedent `ComprehensionRepositoryKey` already set.

**Three decisions worth review:**

1. **`dueOn` decodes as a `String`, not a `Date`.** The shared decoder parses date-*times*, and a scheduling day is not an instant — turning it into one would invent a timezone the backend never chose. Stage 3 is where it stops being opaque.
2. **A re-translate resets the button to its offer.** `translate()` already drops the explanation and the record; the collected state joins them, because the card that was just kept belonged to the previous text/language pair. Without this, editing the text and translating again would show "In your vocabulary" about a card holding the *old* wording.
3. **A failure reuses the same button rather than offering a separate retry.** Nothing was spent and nothing is half-done, so trying again is simply doing it again — unlike the explanation, where a retry is its own action with its own cost.

## Verification

`BUILD SUCCEEDED`, then `TEST SUCCEEDED` across the whole `vista_comicTests` target (71.6s), then a second targeted run confirming the new suites actually execute rather than being silently skipped — 9 tests, all passing:

- The card carries the right source reference and target language.
- The **corrected** text is what gets collected, not the raw recognition.
- Whatever translation is on screen is the one stored.
- A line already in the deck comes back as collected rather than as an error, since the backend answers 200 for a duplicate.
- A failure becomes `.notCollected` rather than a thrown error.
- `collectingNeverSpendsARequest` is a **structural** guard: `collectSelection` takes a `StudyRepository` and nothing else, so there is no route from adding a word to the daily Claude budget. The test exists to fail if that signature ever grows a `ComprehensionRepository`.
- `dueOn` stays a date string.

No XCUITest was written, built, or run.

## Device checklist for the repo owner

On one compact phone and one larger phone:

1. Select a line, correct the OCR, tap Translate. **Add to vocabulary** appears under the translation, above the 深入解釋 offer.
2. Tap it. It shows a brief adding state, then **In your vocabulary** with no way to remove — that absence is deliberate for this stage.
3. Check the button never overflows or truncates beside the depth picker and the explain button, on the narrow phone especially.
4. Select the same line again in a fresh sheet: adding it a second time still ends in the collected state, and `GET /cards` holds one card, not two.
5. **Order matters, and this is the case worth looking at closely.** On one selection, tap 深入解釋 first, wait for the explanation to land so the translation column switches to the cloud wording, *then* add. Confirm the stored card holds the **cloud** translation. On another, add straight after Translate and confirm it holds the on-device one.
6. Correct the OCR text, translate, add, then edit the text again and translate again — the button returns to its offer rather than claiming the new text is collected.
7. With the backend stopped: the button reports it could not add, the translation stays on screen untouched, and tapping again once the backend is back works. (Queueing this instead is ticket 04.)
8. Clear the text entirely: the button is disabled, matching Translate.

## What the device pass actually established

Checked against the database rather than taken from the screen, because two of
the items cannot be seen from the sheet.

**Verified.** The button's position and states, the layout on both phone sizes,
the disabled state on empty text, the reset after a re-translate, the failure
path with the backend stopped, and — from the data — that collecting the same
line twice leaves **one** card: no `(normalized_key, target_language)` pair has
more than one row.

**Item 5(b) verified.** One card's source text appears nowhere in
`comprehension_record`, so no explanation was ever requested for it and the
stored wording can only be the on-device one.

**Item 5(a) NOT established, and the check was inconclusive rather than
failing.** The line used was `SAU KHI`, whose on-device and cloud translations
are both `之後` — identical, so the stored value cannot distinguish which one it
came from. The test has no discriminating power on that input.

To close it, repeat 5(a) on a line whose two translations differ visibly.
`QUÁ ĐÁNG ĐẾN CÙNG LUÔN.` is one already in this deployment's history: on-device
`到最後都太多了。`, cloud `真的是太應該了。` A card holding the latter closes the
item; one holding the former is a real defect.

This is worth closing rather than waving through: "the card keeps the wording
the reader approved" is the behaviour the whole manual-add quality gate rests
on, and it is invisible from the screen.
