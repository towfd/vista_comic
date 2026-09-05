# 01 — Editable translation, and the reader's wording as the single downstream source

**What to build:** After the reader taps Translate on the OCR result screen, the
translated text becomes directly editable, the same way the recognized Vietnamese text
above it already is. Whatever wording sits in that field when the reader acts is what
gets used everywhere else: the card saved into 單字庫, and the context sent with a
深入解釋 request.

This gives the reader a fast, free path that does not exist today — understand the
panel, fix the machine's wording, add it to 單字庫 — without spending one of the day's
limited 深入解釋 requests just to get usable wording.

The ticket also fixes an existing inconsistency: collecting reads the displayed
(cloud-preferred) translation while an explanation request reads the raw on-device one.
They coincide today only by accident of timing. After this, both read the one value the
reader is looking at.

Three events write to the field, and their rules are the load-bearing part of this
ticket — getting them wrong is silent loss of the reader's typing:

| Event | Effect on the field |
| --- | --- |
| Translation succeeds | Reset to the new machine translation |
| Cloud translation arrives from 深入解釋 polling | Overwritten, once |
| Reader types | Holds what they typed |

The once-only nature of the cloud overwrite is a property of the existing polling, not
new logic: the poll returns as soon as the record leaves an in-progress status, and the
poll task's identity does not change when the record is replaced. Edits made after the
cloud answer must survive.

Everything below is mutually load-bearing. Removing any one part leaves a screen that
either loses the reader's work or misreports what it will do with it.

**Blocked by:** None — can start immediately.

**Status:** done — device-verified by the repo owner, 2026-09-06 (branch
`feat/translation-editing`). No automated tests by decision; see the spec's Testing
Decisions.

- [ ] The translation column is an always-editable text editor — no view/edit toggle, no
      pencil affordance — seeded with the machine translation when one lands.
- [ ] The original and translation stay side by side; the editor is usable at compact
      phone width.
- [ ] Adding to 單字庫 saves the wording currently in the field, for both the word and
      the sentence buttons.
- [ ] Requesting 深入解釋 sends the wording currently in the field as its translation
      context.
- [ ] Re-translating — after changing the target language, or after editing the source
      text — resets the field to the new machine translation, discarding any edit.
- [ ] A cloud translation arriving from a 深入解釋 request replaces the field's contents.
- [ ] Edits made *after* the cloud translation has arrived are never overwritten, however
      long the screen stays open.
- [ ] While the field is empty or whitespace-only, both 加入單字庫 buttons and the
      深入解釋 button are disabled; typing one character re-enables them.
- [ ] No explanatory error text accompanies the disabled state — the empty field sits
      directly above the greyed buttons.
- [ ] Once a card exists for this line — just added, or recognised as previously
      collected — the field becomes read-only. Corrections to an existing card are made
      in 單字庫's card detail screen.
- [ ] The translation field leaves autocorrect enabled, diverging from the source field,
      which keeps it disabled. The divergence is explained in a code comment so it does
      not read as an oversight.
- [ ] The result screen dismisses the keyboard on scroll, so the collect buttons stay
      reachable after typing.
- [ ] No backend, schema, endpoint, or repository-protocol change. `Translator`,
      `StudyRepository` and `ComprehensionRepository` keep their current signatures.
- [ ] No view-model extraction or other restructuring of the result screen.
- [ ] New user-facing strings are added to the app's string catalog via Xcode extraction.
- [ ] Existing unit tests still pass, unmodified. No new automated tests — see the spec's
      Testing Decisions for why this is a decision rather than an omission.
- [ ] No XCUITest is written, built, or run. The deliverable in its place is a hand-off
      list pointing at the spec's manual verification checklist, items 1–9 and 11–15.
