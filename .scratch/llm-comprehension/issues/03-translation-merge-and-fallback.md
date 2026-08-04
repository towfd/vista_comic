Type: grilling
Status: resolved

# Translation merge and fallback

## Question

Does the new LLM comprehension call replace or sit alongside M8's dedicated `Translator`/`AppleTranslator` (on-device Apple `Translation` framework), and what happens when the cloud call fails?

## Answer

**Merge translation and explanation into a single structured Claude call**, replacing `Translator` as the primary path — rather than running a separate dedicated-translation pass alongside a new explanation pass. Reasoning: the cloud call already receives visual context (the page image, per ticket 02) that `Translator` never had access to, so a context-aware translation is expected to be at least as accurate as a context-blind one, and a single call avoids the two models disagreeing on ambiguous text (e.g. pronoun or tone choices a bare text-only translator can't disambiguate without seeing the panel).

**`Translator`/`AppleTranslator` is kept, not deleted** — repurposed as an **offline/cloud-failure fallback**: if the Claude call fails (network down, API error, rate limit), the reader falls back to the existing on-device literal translation rather than a hard failure screen. This preserves M8's original "translation doesn't need extra network beyond page loading" property as a degraded-but-working fallback, now that the primary path depends on network for the richer, cloud-driven explanation.

**Arbitrary user-selectable target language remains supported** — this flexibility was an explicit ask, not dropped in the merge. Cross-language reliability of the merged approach for non-default target languages is left as an open risk, not yet validated (see ticket 06).

## Comments

Resolved via a `/grilling` session on 2026-08-01, in the same conversation that created this map.
