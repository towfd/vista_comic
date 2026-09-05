# 02 — An "edited" state for the translation provenance marker

**What to build:** The small capsule beside the translation heading currently answers
"who produced this wording" with two answers: the device, or the cloud. Once the reader
can edit the translation there is a third answer, and without it the screen claims text
the reader typed came from a machine.

After this ticket the marker reports the reader's own edit as such, and reverts to the
machine answer whenever the field goes back to machine wording — which happens on every
re-translate and when a cloud translation arrives.

This is the one part of the feature that does not break anything by being absent: the
marker is merely inaccurate, nothing is lost or mis-saved. It is separated from ticket 01
because it is the only change outside the reader's result screen — the marker is a shared
view — and because it carries its own regression risk in the accessibility identifiers
that existing UI tests depend on.

The screen's established standard is that it does not assert what it cannot support: the
collected label deliberately stays vague for a card with no recorded kind rather than
inventing one. An "on device" marker beside text the reader wrote fails that standard.

**Blocked by:** 01 — Editable translation, and the reader's wording as the single
downstream source. The marker needs the edited-translation state that ticket introduces.

**Status:** implemented on branch `feat/translation-editing`, 2026-09-06 — builds clean,
awaiting the repo owner's device pass (spec checklist item 10). The "Edited" string still
needs Xcode's own extraction pass into the string catalog; `xcodebuild` from the command
line does not write it.

- [ ] The provenance marker's boolean cloud/device input becomes a three-case value:
      on-device, cloud, reader-edited.
- [ ] The marker shows the edited state whenever the field holds the reader's own
      wording, and is legible at the marker's existing small size.
- [ ] The marker returns to the machine answer after a re-translate, and after a cloud
      translation replaces the field.
- [ ] When the reader has not edited anything, the marker behaves exactly as it does
      today.
- [ ] The existing accessibility identifiers for the on-device and cloud cases are
      unchanged, so the UI test already asserting on the on-device marker keeps passing.
- [ ] The marker's styling, size and placement are untouched — this adds a case, not a
      redesign.
- [ ] Nothing records the edited state outside this screen: no card field, no database
      column, no API change.
- [ ] Existing UI tests are not modified. No XCUITest is written, built, or run; the
      hand-off points at the spec's manual verification checklist, item 10.
