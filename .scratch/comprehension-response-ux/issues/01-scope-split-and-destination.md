Type: grilling
Status: resolved

# Scope split and destination

## Question

Three problems with the shipped M9 comprehension flow were reported together: (1) tapping Translate blocks for a long time on the cloud LLM call, (2) tapping the recognized text to correct it stalls before becoming editable, (3) the explanation comes back in an unpredictable language rather than the reader's own. Do all three belong to one effort, and what does reaching the end of that effort produce — a spec, a locked decision, or an in-place change?

## Answer

**Split into two efforts.** Problems 1 and 3 form this map; problem 2 does not.

Problem 2 (the text-editing stall) is a **performance defect with an unknown root cause**, not a decision. `TextEditor` is a stock SwiftUI control with nothing bespoke about its use here, so the stall is likely something else blocking the main thread — plausibly page-image decoding or layout in the surrounding view. There is nothing to decide until the cause is known, which makes it `/diagnosing-bugs` work, not wayfinding. Deferred to its own effort and recorded in this map's Out of scope.

Problems 1 and 3 belong together because both reshape the same seam — `/comprehend`'s request/response shape and how `CroppedSelectionPreview` renders what comes back — and touching one without the other would mean revisiting the same code twice.

**Destination**: a `spec.md` under `.scratch/comprehension-response-ux/`, matching every prior feature in this repo (M6/M8/M9/remote-access), ready to hand to `/to-tickets`. A lighter "lock the decision and implement directly" route was considered and rejected: problem 1 changes the API's interaction shape (what the client waits for, what arrives later, what is persisted when), which is exactly the kind of change this project has consistently specced before building.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map.
