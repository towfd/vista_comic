Type: grilling
Status: resolved

# Destination and scope

## Question

The request is "read our manga on my computer through a web page, add vocabulary from it, and OCR too — the complete set." What is the web client's relationship to the shipped iOS app, how much of the app does "the complete set" cover, and what does reaching the end of this map produce?

## Answer

**Feature parity with the iOS app, including review.** Not a reduced companion: browsing, reading, selecting, OCR, translation, collecting cards, and the whole spaced-repetition review flow all exist on the web.

**The destination is the architecture, not a spec.** This map locks the cross-cutting decisions and splits the work into parts; each part then gets its own `/grilling` session and its own spec, which is how this repo already works (see the `feedback_grill-each-spec-before-writing` preference). A single spec covering the whole web client was considered and rejected as too large to grill honestly in one pass.

The split itself is recorded in [The six-part split](09-the-six-part-split.md).

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
