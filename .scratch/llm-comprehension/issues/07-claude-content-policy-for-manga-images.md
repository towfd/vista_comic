Type: research
Status: resolved

# Claude content policy for manga images

## Question

What is Claude's content/usage policy around analyzing manga page images that may include copyrighted art, stylized violence, or mature themes — under what circumstances would a request be refused, and does refusal behavior differ between text-only and image-input requests?

This determines whether "model refusal" needs to be a first-class, distinguishable failure case (mirroring `OCRRecognizer`'s `noTextFound`/`lowConfidence`/`underlying` pattern) in the new comprehension seam's error handling, and feeds directly into ticket 08's fallback-UX design.

Resolve via a `/research` subagent.

## Answer

The long-form write-up this summary was drawn from lived only on a throwaway agent branch and was deleted on 2026-08-09; what follows is the whole of the finding now. It is a summary of published Anthropic documentation as it stood on 2026-08-01, not a durable guarantee — re-check the sources if a decision turns on it.

**1. No manga/comic- or copyright-specific policy exists.** Anthropic's Usage Policy (anthropic.com/aup) has zero occurrences of "manga," "comic," "fair use," "transformative," or "personal use" (confirmed by full-text search). Refusal risk is **content-driven, not copyright-driven**: the same universal rules apply regardless of subject matter — graphic violence/gore (including sexual violence) and sexually explicit content are the actual triggers, and manga spans genres (seinen, horror, ecchi) where panel content could plausibly cross those lines independent of copyright. The IP-infringement clause in the policy is about *using Claude to infringe* (e.g. reproduce/redistribute art), not about *analyzing* copyrighted input — nothing bars viewing/translating/describing a copyrighted image.

**2. Refusal behavior differs only narrowly by modality.** Content standards are written modality-agnostically, but the Vision docs add two image-specific hard limits with no text-only equivalent: refusing to identify real people in photos, and an outright "does not process" framing for inappropriate/explicit images (vs. declining to continue a text reply). Separately — and most actionable for this app — Claude's newer API surface exposes refusals as a **structured signal**: `stop_reason: "refusal"` with a `stop_details.category` field (`cyber`/`bio`/`frontier_llm`/`reasoning_extraction`/`general_harms`), documented for Claude Fable 5/Opus 5. It's an HTTP 200, not an error — explicitly called out as invisible to normal error-rate monitoring. **Open caveat, not resolved by this research:** it's undocumented whether cheaper models (Sonnet/Haiku — the tier this app is cost-sensitive toward per ticket 05) surface the same structured `stop_details`, or only a natural-language refusal in ordinary response text. Needs empirical confirmation once ticket 06 picks a model tier.

**3. No documentation addresses personal/transformative use either way.** Zero hits for "fair use"/"transformative"/"personal use" anywhere in the Usage Policy or Claude's Constitution. The one Anthropic copyright statement found (a commercial-customer indemnification against third-party infringement claims) is a legal risk-transfer mechanism, unrelated to whether a given image gets processed, and doesn't distinguish personal use.

**Implication for ticket 08 (fallback UX):** "model declined" is worth treating as a distinguishable failure case (mirroring `OCRRecognizer`'s pattern) given the structured `stop_reason: "refusal"` signal exists on at least some models — but ticket 08 should verify empirically, against whichever model ticket 06 selects, whether that structured field is actually present before designing UI around it (it may just be an unstructured refusal in plain response text on cheaper tiers).
