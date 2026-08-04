# LLM-assisted comprehension — wayfinder map

## Destination

A `spec.md` under `.scratch/llm-comprehension/`, ready to hand to `/to-tickets` — same shape as `.scratch/ocr-translation/spec.md`. It extends M6's OCR selection flow and M8's translate-and-save flow with richer, LLM-assisted comprehension (beyond literal translation), realizing README roadmap item 4's remainder ("word, sentence, and context explanations" and "LLM-assisted comprehension"). This map only covers extending the existing per-selection select → OCR → explain flow — not a new interaction model (see Out of scope).

## Notes

- M8's spec (`.scratch/ocr-translation/spec.md`) explicitly deferred this scope: *"Word/sentence/context explanations and any LLM-assisted comprehension — explicitly deferred to a separate future `/wayfinder` effort."* This map is that effort.
- Consult `/grilling` and `/domain-modeling` for remaining open questions; `/research` for external API/policy facts; `/prototype` for UI or model-output spikes needing a concrete artifact to react to.
- Standing constraint: single-user, single-device app (no accounts, no per-user identity — see `docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md`). Keep solutions single-user-simple; don't design multi-tenant machinery.
- The developer's iPhone is a 14 Plus (no A17 Pro) — rules out Apple's on-device Foundation Models framework for this effort. Revisit only if the reference device changes (see Not yet specified).

## Decisions so far

- [Destination & processing timing](issues/01-destination-and-processing-timing.md) — destination is a `spec.md`; processing is real-time/per-selection, not a batch/Celery pipeline over a whole downloaded manga.
- [Model location & input context](issues/02-model-location-and-input-context.md) — cloud Claude API, pay-per-token (on-device ruled out: the dev's iPhone 14 Plus lacks the required A17 Pro); each request sends the full-resolution selection crop plus a downscaled (~1024px) full-page image for visual context.
- [Translation merge & fallback](issues/03-translation-merge-and-fallback.md) — merges translation and explanation into one Claude call, replacing M8's `Translator` as the primary path; `Translator`/`AppleTranslator` is kept, repurposed as the offline/cloud-failure fallback.
- [Structured output & persistence](issues/04-structured-output-and-persistence.md) — output is schema-enforced, not free text; explanation content is persisted alongside the translation in `saved_translation`/單字本, not view-only.
- [Cost safety net](issues/05-cost-safety-net.md) — a simple global daily request cap (no per-user system exists to key a quota off of).
- [Claude content policy for manga images](issues/07-claude-content-policy-for-manga-images.md) — no manga/copyright-specific policy exists; refusal risk is content-driven (violence/gore/sexual content), not copyright-driven; refusals can surface as a structured `stop_reason: "refusal"` signal on some models, unconfirmed for cheaper tiers.
- [Daily cap value and enforcement](issues/10-daily-cap-value-and-enforcement.md) — a small Postgres table (not Redis — no decided caching need yet to justify it), 300 requests/day, global anomaly guard.
- [Schema fields and model tier](issues/06-schema-fields-and-model-tier-prototype.md) — validated against real content: `translation`/`grammar_notes`/`context_notes`/`tone_register` via a strict tool-use schema; defaults to Claude Haiku 4.5 with a manual user upgrade to Sonnet 5; cross-language reliability beyond the default Vietnamese→Traditional Chinese path is an accepted, unverified assumption.
- [Result screen and fallback UX](issues/08-result-screen-and-fallback-ux.md) — a persistent status banner (☁️ full/📱 offline/⚠️ declined) at the top of the result screen communicates degradation before any content, chosen over disclosure and tabbed layouts.
- [Backend API contract and schema](issues/09-backend-api-contract-and-schema.md) — new flat `POST /comprehend` endpoint (separate from `/translations`'s save/list role); sends the user-corrected OCR text explicitly rather than letting Claude re-derive it; a lenient per-request image-size ceiling as a second cost-anomaly guard; success/declined discriminated by a `status` field on HTTP 200, not by status code; `saved_translation` gains three nullable columns (`grammar_notes`, `context_notes`, `tone_register`), no separate provenance column.

## Not yet specified

- Revisiting on-device (Apple's Foundation Models framework) if the developer's reference hardware later changes to something A17 Pro-class or newer — not sharp enough to ticket now, purely a "reconsider if circumstances change" note.
- Whether README's "LLM-assisted comprehension" eventually grows past the per-selection flow into something like free-form, chat-style Q&A about a passage — deliberately not pursued by this map (see Out of scope), but the door isn't closed on a future, separate effort.

## Out of scope

- Free-form, chat-style comprehension Q&A beyond the existing per-selection select → OCR → explain flow. This map only extends M6/M8's existing interaction model; a conversational interface would be its own future effort.
