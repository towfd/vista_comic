Type: grilling
Status: resolved

# Structured output and persistence

## Question

Should the comprehension call's output be structured (schema-enforced) or free text, and does the richer explanation content get persisted alongside the translation in `saved_translation`/單字本, or is it view-only?

## Answer

**Structured output, schema-enforced** — not free text parsed after the fact. Cloud providers support this natively (Claude's tool-use-based structured output), matching in spirit Apple's `@Generable`/`@Guide` constrained decoding, which was the original motivating comparison before the on-device path was ruled out (ticket 02). This mirrors the existing project pattern of typed protocol boundaries (`OCRRecognizer`, `ComicRepository`) rather than raw strings passed between layers.

**Explanation content is persisted**, not ephemeral/view-only. The `saved_translation` table and its API gain new fields to hold the explanation content alongside the existing original/translated text pair; the 單字本 list stays visually simple but gains the ability to expand into the full saved explanation. Rationale: this feature's whole point is deeper comprehension — if the explanation isn't saved, revisiting a 單字本 entry later only shows the shallow M8-era literal translation, undermining the reason this map exists.

The exact schema/field list and the exact `saved_translation` column additions are deferred (see tickets 06 and 09) — this ticket only locks that structured output + persisted explanation is the shape, not the specific fields.

## Comments

Resolved via a `/grilling` session on 2026-08-01, in the same conversation that created this map.
