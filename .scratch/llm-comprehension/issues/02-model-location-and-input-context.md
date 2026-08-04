Type: grilling
Status: resolved

# Model location and input context

## Question

Should the comprehension/explanation model run on-device (Apple's Foundation Models framework) or via a cloud LLM API, which provider, and what visual/textual context gets sent per request?

## Answer

**Model location: cloud (Claude API), not on-device.** Apple's third-generation Foundation Models framework (announced WWDC 2026) does support Vietnamese and, as of the 2026 update, does accept image input — which briefly made on-device attractive: it matches this app's existing on-device-first pattern for OCR (Vision) and translation (`Translation` framework), introduces no new network dependency, and has no per-call cost. But the framework requires an iPhone 15 Pro or newer (A17 Pro chip) and iOS 26+ — the developer's actual device is an iPhone 14 Plus, which cannot run it at all, regardless of its other merits. On-device is therefore ruled out for this effort (see the map's "Not yet specified" for revisiting this later).

**Provider: Claude API**, accepting pay-per-token billing. Confirmed (research, 2026-08-01) that no consumer subscription — Claude Pro/Max, ChatGPT Plus, Gemini Advanced/Google AI Pro — can be used as API access: subscriptions and API billing are separate products/billing tracks on all three platforms in 2026. The one unofficial bridge (extracting a Claude Max OAuth token for third-party API proxies, e.g. CLIProxyAPI) was explicitly blocked by Anthropic in April 2026 (OAuth-token extraction itself was shut down in January 2026) and would violate Anthropic's terms even where technically possible. Gemini's free API tier (Google AI Studio) was noted as a genuinely free alternative but not chosen, given the stated preference for Claude's quality and ecosystem fit (this project's own tooling is Claude Code).

**Request context: two images per request** — the existing selection crop, sent at original resolution (precision on what's actually being asked about), plus the full page image, downscaled (~1024px long edge), purely for scene/panel/speaker visual context, not for re-reading text (that remains the crop + the existing OCR result's job). Full resolution isn't needed for the page-context image since it only needs to convey coarse visual context, not legible text — this keeps cloud image-token cost down given a reader may issue several per-selection queries against the same page.

Not using on-device removes the need to raise `IPHONEOS_DEPLOYMENT_TARGET` past its current 18.1 — an incidental simplification of this decision.

## Comments

Resolved via a `/grilling` session on 2026-08-01, including live research on Apple Foundation Models hardware/language requirements and 2026 LLM-subscription-vs-API billing terms, in the same conversation that created this map.
