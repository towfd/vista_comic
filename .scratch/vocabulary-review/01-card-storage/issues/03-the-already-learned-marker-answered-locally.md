# 03 — The already-learned marker, answered locally

**What to build:** Selecting a line the reader has collected before tells them so — and still shows the meaning in full, because they clearly did not remember it.

This is the smallest version of the reward the whole PRD is built around: being told, while reading, that you already know this. It exists this early because it costs almost nothing here, and because the lookup count it enables is what stage 3 reads as a forgetting signal.

**It is answered from a local snapshot, not an endpoint.** The deck is a few hundred short strings, so the phone can hold all of it. That is the only arrangement in which the marker survives the situation the reader is most often in — a downloaded chapter and no signal. The snapshot stores the **raw `GET /cards` bytes** for the reason `CatalogSnapshotStore` gives: the display models are `Decodable`-only and should stay that way.

**This ticket implements the normalisation a second time, in Swift.** It must pass `spec.md`'s vector table verbatim, the same one ticket 01 tested in Python. A disagreement between the two shows up as the app saying "not collected" while the server says "duplicate", which is a confusing failure to chase later and a cheap one to prevent now.

The marker is a courtesy, never a correctness requirement: when the snapshot is missing, empty or unreadable, the answer is "not collected" and nothing breaks.

**Blocked by:** 02.

**Status:** implemented on branch `feat/learning-card-store`, 2026-08-19 — `BUILD SUCCEEDED`, `TEST SUCCEEDED` across `vista_comicTests`, 22 new tests passing. **Awaiting the repo owner's device pass** (checklist below).

- [x] The snapshot stores raw response bytes rather than re-encoded models
- [x] Swift normalisation passes `spec.md`'s vector table verbatim, matching ticket 01's Python results
- [x] Selecting a previously collected line shows the marker and still shows the full meaning
- [x] The button starts in the collected state for a line already in the deck
- [x] A missing, empty or malformed snapshot means "not collected", surfaces no error, and blocks nothing
- [x] The snapshot refreshes after a successful list or add, and on app foreground
- [x] The marker works with no network, from the snapshot alone
- [x] A line collected with hard line breaks matches the same line without them
- [x] No XCUITest is written; a device checklist is handed to the repo owner

## What was built

- `Networking/TextNormalization.swift` — `normalizedKey(_:)`. NFKC via `precomposedStringWithCompatibilityMapping`, then every whitespace character removed, then `lowercased()` — locale-independent, so a device set to Turkish does not compute a different key than the server did.
- `Networking/DeckSnapshotStore.swift` — protocol, file-backed and in-memory stores, holding the **raw `GET /cards` bytes**. One file, not a directory: the reader has one vocabulary.
- `SelectionActions.alreadyCollected(_:targetLanguage:in:)` — pure, takes cards rather than a repository, so the rule is testable with no network seam near it.
- `StudyRepository.knownCards()` — neither `async` nor `throws`, deliberately. It is a local read on the path of an action the reader is waiting on, and an absent snapshot is simply an empty deck.
- `CroppedSelectionPreview` — a `.alreadyKnown` state, checked when the translation lands.
- `RootTabView` — refreshes the snapshot on appear and on returning to the foreground.

**Three decisions worth review:**

1. **`collect` awaits a snapshot refresh rather than firing one off.** The add already costs a round trip and a second is cheap beside it, whereas a detached task would make "is the snapshot current?" depend on timing. Without this, a word collected in this session is not recognised until the app is backgrounded and reopened.
2. **`alreadyKnown` is worded differently from `collected`.** One says "kept"; the other says "you kept this before, and here you are again" — which is the reward this whole feature is built around, and it is only true in the second case. **The translation stays in full underneath it**: being told you have seen a word before is not a reason to withhold what it means, since the reader is looking it up precisely because they did not remember.
3. **The check runs when the translation lands, not on appear.** Recognition runs automatically and the reader corrects it afterwards, so anything earlier would match against a line they had not finished fixing.

## Verification

`BUILD SUCCEEDED`, `TEST SUCCEEDED` across the whole `vista_comicTests` target, then a targeted run confirming all three new suites execute — **22 tests, no failures**:

- The eight shared normalisation vectors, parameterised, plus inflected forms staying distinct. **This table is copied verbatim from `backend/tests/test_learning_cards.py`**, which is the entire guard against the two implementations drifting apart.
- Matching: exact line; a line the OCR broke differently; half-width and spacing differences; a word collected for another language is **not** a match; an uncollected word is not a match; an empty deck answers no; whitespace alone matches nothing.
- The snapshot: round trip, empty store, replacement, survival across a rebuild over the same directory (what a relaunch does), unreadable bytes degrading to an empty deck rather than crashing, and an absent snapshot doing the same.

No XCUITest was written, built, or run.

## Device checklist for the repo owner

The deck currently holds two cards, both Vietnamese → 繁體中文: the long `SAU KHI THÔNG QUA ĐẠO LUẬT...2011` line, and `SAU KHI` on its own. Both are usable below.

**Before anything else**: launch the app once with the backend reachable, so the snapshot gets its first fetch. Until that happens there is nothing to match against, and no marker is a correct answer rather than a bug.

1. Re-select the `SAU KHI` line and translate it. **You've learned this before** appears, **and the translation is still shown in full**. The second half matters as much as the first.
2. Re-select the long 2011 line. Same marker, and it matches that card rather than the short one — the two are different cards, not one containing the other.
3. Frame a line you have never collected. **No marker**, and the ordinary Add to vocabulary offer.
4. **Collect a new word, dismiss the sheet, then immediately re-select the same line without leaving the app.** The marker appears. This is the case the awaited snapshot refresh exists for; before it, this showed nothing until the app had been backgrounded.
5. **Airplane mode.** Re-select an already-collected line: the marker still appears, because it is answered from the snapshot on disk rather than the network. This is the point of the whole ticket.
6. Change the target language in the picker and re-translate a collected line: **no marker**, because a card is a word *plus* a language.
7. Select a bubble whose OCR breaks the line differently from when you collected it (or add a line break by hand before translating). Still the same card, still marked.
8. Both phone sizes: the marker sits where the Add button was and does not disturb the layout of the depth picker or the explain button.
