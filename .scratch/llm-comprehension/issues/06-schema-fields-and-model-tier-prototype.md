Type: prototype
Status: resolved

# Schema fields and model tier prototype

## Question

What exact fields does the comprehension output's structured schema contain (e.g. translation, grammar notes, example sentence, sense disambiguation, tone/register notes — or some subset of these), and which Claude model tier (Haiku/Sonnet/Opus) reliably produces it for real Vietnamese manga dialogue?

These two questions are coupled — the schema can't be locked without knowing what the chosen model can actually produce reliably for this language pair and content type, and the model tier can't be judged without a concrete schema to test it against. Also needs to sanity-check cross-language reliability for non-default target languages (ticket 03's open risk), not just the default Vietnamese→Traditional Chinese path.

Resolve via `/prototype`: draft a candidate schema, then run it against a handful of real page crops + full-page images from the actual manga library (ticket 02's input shape) through candidate Claude tiers, and see what holds up.

## Answer

**Schema fields (validated against real content):** `translation` (Traditional Chinese), `grammar_notes`, `context_notes` (how the page image resolved ambiguity), `tone_register`. Sent as a `strict: true` tool-use schema (`additionalProperties: false`, all four fields `required`) — both tiers below returned fully schema-conforming output with no parsing issues.

**Prototype method:** a real page (`marrymyhusband/01-bai1/005.jpg`, from the actual library at `MANGA_LIBRARY_PATH`) with a genuinely ambiguous case — Vietnamese "anh/em" kinship pronouns, which require relationship context (not just text) to translate correctly. Cropped one speech bubble (original resolution) + downscaled the full page (~1024px), matching ticket 02's input shape exactly, then called the real Claude API with both.

**Model tier: default Claude Haiku 4.5, with a manual user-facing upgrade to Claude Sonnet 5 if quality is insufficient.** Both tiers produced correct, schema-conforming translations and genuinely used the page image (both correctly described the speaker's shirt/tie/coffee cup, not just the text). Sonnet's explanation was noticeably deeper — it cross-referenced the page's *second* speech bubble to reason about who "em" refers to, where Haiku's explanation was more textbook-generic and didn't connect the two bubbles. The quality gap is real but not enormous, and Haiku is correct, not broken — matches the "start cheap, let the user opt into the stronger model" pattern discussed for ticket 05's cost sensitivity. Real costs observed: Haiku ~$0.0035/request (1814 in / 348 out tokens), Sonnet ~$0.013/request (1841 in / 525 out tokens) — both negligible for personal use, Sonnet roughly 3-4x Haiku's cost.

**Cross-language reliability (the open risk from ticket 03) — deliberately not empirically tested.** Only the default Vietnamese→Traditional Chinese path was validated. The user's call: primary usage is Traditional Chinese, and English (the next most likely alternate target) is expected to perform at least as well given English's dominance in LLM training data — so this is accepted as a reasonable-but-unverified assumption, not re-tested now. Revisit only if a real quality problem surfaces for a non-default target language in practice.

## Comments

Resolved via `/prototype` on 2026-08-03 — two real Claude API calls (Haiku 4.5, Sonnet 5) against a real page from the manga library, in the same conversation that created this map.
