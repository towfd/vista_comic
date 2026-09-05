Status: ready-for-agent

# Translation editing: the reader's wording is the answer, not the machine's

## Problem Statement

The reader selects a speech bubble, corrects the OCR, taps Translate, and gets an
on-device translation. Often it is *nearly* right — the words are there but the sense
is off, and the reader can see exactly what it should say because they already
understand the panel. Right now they cannot say so. The translation column is
read-only.

That leaves two bad options. Either they add the line to 單字庫 with a translation they
know is wrong — poisoning the deck the whole vocabulary feature depends on — or they
spend one of today's limited requests on 深入解釋 and wait minutes for a cloud answer,
purely to fix wording they could have typed in three seconds.

The second option is the expensive one and it is being taken for the wrong reason.
深入解釋 exists for lines the reader *does not understand*. Using it as a spell-checker
burns quota and time on a problem the reader has already solved in their head.

## Solution

Make the translation column editable, exactly the way the recognized text above it
already is. The result screen then reads as one consistent rule: **the machine produces
a draft, the reader produces the final version** — for the Vietnamese source and for the
translation alike.

Whatever wording is in that field when the reader acts is what everything downstream
uses: the card saved into 單字庫, and the context sent with a 深入解釋 request. The
provenance chip beside the translation grows a third state so the screen never claims a
line the reader typed came from the device or the cloud.

The reader gains a fast, free path that did not exist: understand the panel → fix the
wording → add to 單字庫, with no network call, no request spent, and no waiting.

## User Stories

1. As a reader, I want to edit the translated text directly, so that I can correct a
   machine translation whose sense is wrong without leaving the screen.
2. As a reader, I want editing the translation to work the same way as editing the
   recognized source text, so that I do not have to learn two different interactions on
   one screen.
3. As a reader, I want the translation field to be editable immediately when the
   translation appears, so that correcting it does not cost me an extra tap on the most
   common thing I do here.
4. As a reader, I want the original and my corrected translation to stay side by side,
   so that I can still check my wording against the Vietnamese while I type it.
5. As a reader who understands a panel but got a poor translation, I want to fix the
   wording and add it straight to 單字庫, so that I do not have to spend a 深入解釋
   request just to get a usable card.
6. As a reader, I want my corrected translation to be what gets saved to 單字庫, so that
   the deck contains wording I have actually confirmed rather than machine output I
   silently disagreed with.
7. As a reader who does ask for 深入解釋, I want my corrected translation sent along as
   the context, so that the explanation is written against the meaning I settled on.
8. As a reader who did not understand the panel, I want to request 深入解釋 first and
   correct the cloud's translation afterwards, so that the deeper answer is my starting
   point rather than something I have to reconcile with my own guess.
9. As a reader, I want a cloud translation arriving from 深入解釋 to replace what is in
   the field, so that the better answer I explicitly waited minutes for is the one I end
   up looking at.
10. As a reader, I want the cloud translation to replace the field only once — when it
    arrives — so that corrections I make after reading it are never undone by continued
    background polling.
11. As a reader, I want re-translating (after changing the target language, or after
    fixing a typo in the source) to reset the translation field to the new machine
    output, so that the field never shows wording that belongs to a different language
    or a different source line.
12. As a reader, I want a visible marker telling me the translation on screen is my own
    edit rather than the device's or the cloud's, so that the screen never misreports
    where the wording came from.
13. As a reader, I want the existing "On device" and "Cloud" markers to keep behaving as
    they do today when I have not edited anything, so that this change does not alter
    the screen I already know.
14. As a reader, I want "加入單字庫" and "深入解釋" to be unavailable while the
    translation field is empty, so that I cannot create a card with no answer side or
    ask for an explanation of nothing.
15. As a reader, I want the disabled buttons to sit directly under the empty field, so
    that the reason is obvious without the screen printing a warning at me.
16. As a reader who has just added a card, I want the translation field to stop being
    editable, so that I am never typing into a field whose changes go nowhere.
17. As a reader who is looking up a line I collected before, I want the same rule — the
    field is read-only because the card already exists, so that there is exactly one
    place a saved card gets edited.
18. As a reader, I want to be told, by the field simply not accepting input, that further
    corrections belong in 單字庫's own card screen, so that I do not end up with the
    reader and the deck disagreeing about what a card says.
19. As a reader typing in my own language, I want autocorrect and input candidates
    available in the translation field, so that Chinese input is usable at all.
20. As a reader, I want the source field to keep autocorrect switched off, so that the
    deliberate Vietnamese corrections I make there are not rewritten, and the keyboard
    still opens quickly.
21. As a reader, I want to dismiss the keyboard by scrolling, so that after typing a
    translation I can still reach the buttons underneath it.
22. As a reader on a compact phone, I want the editable translation column to remain
    usable at that width, so that the feature is not effectively large-phone-only.
23. As the developer, I want no backend, schema, or repository-protocol changes, so that
    a wording-level UI improvement cannot break persistence or the study scheduler.
24. As the developer, I want the existing accessibility identifiers for the on-device and
    cloud provenance markers preserved, so that the UI tests already referencing them
    keep working.
25. As the developer, I want the two downstream actions to read the translation from one
    place, so that the card and the explanation request can never disagree about which
    wording the reader was looking at.

## Implementation Decisions

### The editable field

- `CroppedSelectionPreview`'s translation column becomes a `TextEditor` bound to new
  view state, replacing the read-only `Text`. It is always editable while it is editable
  at all — no view/edit mode toggle, no pencil affordance. This mirrors the recognized
  source text directly above it, which is already an always-editable `TextEditor` seeded
  from OCR output.
- The side-by-side original/translation layout is kept. It is a deliberate decision from
  the `ocr-translation` spec (user story 5 there) and this spec does not overturn it. The
  editor gets a minimum height so it is tappable and shows a couple of lines of Chinese;
  the compact-phone width is a manual-verification item rather than a design change.
- The new state is seeded exactly the way `editedText` is seeded from a successful
  recognition: when a translation lands, its text becomes the draft in the field.

### Which wording wins, and when it is overwritten

Three events can write to the field. Their rules are fixed here because getting them
wrong is silent data loss:

| Event | Effect on the field |
| --- | --- |
| Translation succeeds (`translate()`) | Field is **reset** to the new machine translation |
| Cloud translation arrives via 深入解釋 polling | Field is **overwritten**, once |
| Reader types | Field holds what they typed |

- **Cloud wins over a reader edit.** This follows the reader's two actual flows: either
  they understand the line and edit without ever asking for an explanation, or they do
  not understand it, ask, and edit *after* the cloud answers. Editing and then asking is
  not a flow they have. Preserving today's "cloud translation supersedes the on-device
  one" rule is therefore simpler and matches how the screen is used.
- **The overwrite happens at most once, and this is a property of the existing polling,
  not new logic to build.** `awaitRecordFinishing` returns as soon as the record leaves an
  in-progress status, and the poll task's identity does not change when the record is
  replaced — so nothing writes to the record again afterwards. Edits made after the cloud
  answer are safe. This is the single most important behaviour to confirm by hand.
- **Re-translating resets the field.** `translate()` already clears the explanation
  outcome, the record, and the collection state, on the stated grounds that a changed
  source text or target language means "this is not the same thing any more". A reader's
  translation edit belongs to the old text/language pair for exactly the same reason.
  Keeping it would produce a field claiming to be, say, English while showing Chinese.
- **Accepted cost:** a reader who edits the translation, then goes back and fixes a typo
  in the source, then re-translates, loses the edit. Judged acceptable — the source
  changed, so the translation genuinely should be redone.
- **Accepted risk:** if the reader ever does edit and *then* request 深入解釋, their
  wording is replaced without warning when the cloud answers. Accepted on the reader's
  own assessment that this flow does not occur. The mitigation, if it ever bites, is a
  single "has the reader touched this" flag — a small, additive change.

### Downstream consumers

- Both downstream actions read the translation from the new editable state, so the card
  and the explanation request cannot disagree with each other or with the screen.
- This resolves an existing inconsistency: the collect action currently reads the
  displayed translation (cloud-preferred), while the explanation request reads the raw
  on-device translation. They coincide today only because no record exists at the moment
  an explanation is requested. After this change both read one value.
- `collectSelection`, `requestExplanation`, `StudyRepository`, `ComprehensionRepository`
  and `Translator` keep their current signatures. Nothing about the seams changes; only
  which string is handed across them.

### Empty translation

- A new predicate gates the downstream actions on the translation being non-empty after
  trimming whitespace and newlines — mirroring the existing source-text predicate that
  gates the Translate button.
- "加入單字庫" (both kind buttons) and "深入解釋" are disabled while it fails.
- No explanatory error text. The empty field and the greyed buttons are adjacent; the
  cause is self-evident and a warning line would be noise.
- Rationale: the vocabulary PRD makes manual collection the deck's quality gate. A card
  with an empty answer side defeats that gate and can only ever be answered "I don't
  know" during review.

### Read-only once a card exists

- The field becomes read-only in both states where a card for this line already exists:
  just added by this reader, and recognised as previously collected.
- The single editing path for an existing card is 單字庫's card detail screen, which
  already supports editing the translation through `StudyRepository.update`.
- Two reasons this is not a write-back:
  - An offline collection is queued locally and **has no card id**, so there is nothing
    to update. Supporting write-back would require a whole "edit a card that does not
    exist yet" mechanism.
  - It would create a second write path into a card, competing with the detail screen —
    whose update contract deliberately sends the whole form at once to avoid ambiguity.
- Making the field read-only rather than merely inert is the point: a field that accepts
  typing which goes nowhere is precisely the kind of lying UI this screen otherwise
  avoids. The collected state already replaces the buttons with a confirmation label;
  freezing the field makes the input match that statement.
- Accepted cost: a reader looking up a previously collected line with a bad saved
  translation cannot fix it here and must go to 單字庫.

### Provenance marker

- `TranslationProvenanceChip`'s `isCloud: Bool` becomes a three-case enum: on-device,
  cloud, and reader-edited. It has a single call site, so this does not spread.
- The existing accessibility identifiers for the on-device and cloud cases are kept
  unchanged, so the UI test already asserting on the on-device marker is unaffected.
- The chip's styling is untouched; this adds a case, not a redesign.
- Rationale: the screen's established standard is that it does not assert things it
  cannot support — the collected label stays deliberately vague for a card with no
  recorded kind rather than inventing one. A "On device" chip beside text the reader
  typed fails that standard.

### Keyboard and input

- The translation field leaves autocorrect **on**, deliberately diverging from the source
  field, which switches it off. The reasons for switching it off there — a keyboard whose
  language does not match the text, and autocorrect rewriting deliberate corrections — do
  not apply to the reader typing their own language, where candidate input is what makes
  Chinese entry possible at all. The divergence is documented in code so it does not read
  as an oversight.
- Interactive scroll-to-dismiss is added to the result screen's scroll view. With a second
  text field lower down the screen, the keyboard can cover the collect buttons; one
  modifier fixes that and also improves the pre-existing case with the source field. This
  is preferred over a keyboard toolbar, which would require managing focus state.

### Explicitly unchanged

- No backend endpoint, table, or migration.
- No change to `LearningCard`'s shape — nothing records that a translation was
  hand-edited.
- No view-model extraction. `CroppedSelectionPreview` is long and state-heavy and will
  eventually want one, but that is a separate refactor and doing it here would violate
  the rule against broad refactors inside a focused feature.
- New user-facing strings are added to the app's string catalog through Xcode's normal
  extraction.

## Testing Decisions

- **No automated tests are added for this feature. This is a decision, not an omission.**
  The behaviour here is almost entirely SwiftUI view state — which field holds what, when
  it is reseeded, when it is read-only, when a button is disabled — and `@State` inside a
  view is not readable from the test target. The alternative, extracting a view model to
  make it testable, is the refactor this spec explicitly declines.
- **No new seams.** The existing protocol seams (`Translator`, `StudyRepository`,
  `ComprehensionRepository`) are unchanged and already stubbed by the existing flow tests.
  This spec changes which string crosses them, not the boundaries themselves. That keeps
  the seam count where it is, which is the goal.
- The existing unit tests must continue to pass unchanged. Their subjects — the free
  functions in the selection domain — are not modified by this spec.
- **UI verification belongs to the user, per the project's collaboration rules.** No
  XCUITest is written, built, or run for this feature. The deliverable in its place is the
  hand-off checklist below.
- Existing UI tests are not to be modified. The provenance identifiers they depend on are
  preserved for exactly this reason.

### Hand-off checklist for manual verification

Ordered roughly by how likely each is to reveal a problem:

1. **Cloud overwrites exactly once.** Translate, request 深入解釋, wait for the cloud
   answer to land, then edit the translation and keep the screen open for a minute or
   two. The edit must survive — nothing may overwrite it after the answer arrives.
2. **Cloud overwrite reaches the card.** Following on from (1), add to 單字庫 and confirm
   in the deck that the card holds the post-cloud edit, not the on-device wording.
3. **The fast path.** Translate, correct the wording, add as word and as sentence, and
   confirm in 單字庫 that the corrected wording is what was saved — with no 深入解釋
   request spent.
4. **Re-translate resets.** Edit the translation, change the target language, translate
   again: the field must show the new machine translation, and the provenance chip must
   go back to "on device".
5. **Source edit resets.** Edit the translation, then edit the source text, then
   translate again: same expectation.
6. **Empty field.** Clear the translation entirely; both collect buttons and 深入解釋 go
   grey. Type one character; they come back.
7. **Whitespace only.** Same as (6) with spaces and a newline — must still be treated as
   empty.
8. **Read-only after adding.** Add to 單字庫, then try to type in the translation field.
   Nothing should be accepted.
9. **Read-only for a known line.** Look up a line already in the deck (the "You've
   learned this before" state) and confirm the field is read-only there too.
10. **Provenance chip.** Confirm all three states appear at the right times, and that the
    edited state is legible at its small size.
11. **Chinese input.** Confirm candidate selection works in the translation field, and
    that the source field still has autocorrect off.
12. **Keyboard dismissal.** With the keyboard up from the translation field, scroll down
    and confirm the keyboard dismisses and the collect buttons are reachable.
13. **Compact phone layout.** The whole flow on the smallest supported phone — the
    editable column at that width is the most likely layout casualty.
14. **Larger phone layout.** Same flow, confirming nothing stretches badly.
15. **Translation failure path.** Force a translation failure and confirm the retry path
    still behaves, with no stale edited text left behind.

## Out of Scope

- Writing a reader's edit back to a card that already exists, whether saved or queued
  offline. Existing cards are edited in 單字庫.
- Recording anywhere — on the card, in the database, in the API — that a translation was
  hand-edited rather than machine-produced.
- Any backend, schema, endpoint, or repository-protocol change.
- Showing a cloud translation alongside a reader's edit as a comparable suggestion with
  an "adopt" action.
- Warning or confirming before an action that discards an edit (re-translating, or
  requesting an explanation after editing).
- A "has the reader touched this" flag protecting edits from the cloud overwrite. Named
  here as the known mitigation should the accepted risk above ever bite.
- Extracting a view model from the result screen, or any other restructuring of it.
- Editing the translation from anywhere other than the OCR result screen.
- Changing the side-by-side layout, the target-language picker, the depth picker, or any
  other existing control on the screen.
- Any automated test, unit or UI, for this feature.

## Further Notes

- Decided through `/grilling` across nine questions. The two decisions most worth
  revisiting if the feature disappoints in use are the cloud-overwrite priority (the
  reader may turn out to edit-then-explain after all) and the read-only-after-collect
  rule (which sends the reader to another tab to fix a bad saved translation).
- This is a small spec resting on a large amount of already-shipped work: OCR
  recognition, on-device translation, the collect flow, and the explanation request are
  all in place and unchanged. The feature is the removal of one artificial constraint —
  the translation column being read-only — plus the rules that removal forces into the
  open.
- The economic point is worth restating for whoever picks this up: 深入解釋 is
  rate-limited and slow by design. Every time a reader spends one on a translation they
  could have typed themselves, the budget is going to the wrong problem. That is the
  benefit this feature is actually delivering.
