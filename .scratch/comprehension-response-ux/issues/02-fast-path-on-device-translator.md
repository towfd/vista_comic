Type: grilling
Status: resolved

# Fast path is the on-device translator

## Question

The reader wants a literal translation immediately and is content to wait for the deeper explanation. Where does that immediate result come from?

## Answer

**The existing on-device `Translator` (Apple's `Translation` framework), promoted from "fallback on failure" to "always runs first."** Tapping Translate shows its literal translation right away; the cloud `POST /comprehend` call then runs in the background and fills in `grammarNotes`/`contextNotes`/`toneRegister` when it returns.

This directly reverses M9's [translation merge & fallback](../../llm-comprehension/issues/03-translation-merge-and-fallback.md) decision, which merged translation and explanation into one Claude call precisely so the reader would see a single coherent result. That merge is what makes the current wait feel so long — nothing at all appears until the slowest part finishes. The spec must state this supersession explicitly.

Chosen over two alternatives:

- **Splitting the backend into a fast translation-only endpoint and a slow explanation endpoint.** Rejected: it doubles the Claude calls (and so the per-selection cost) to produce something the on-device translator already produces for free, and it adds a second endpoint's worth of contract, tests, and failure modes.
- **Streaming the Claude tool-use response so fields render as they arrive.** Rejected: tool-use JSON arrives as partial-JSON deltas with no guarantee the four fields complete in a useful order, and this codebase has no streaming infrastructure at any layer. Far more machinery than the problem needs.

The chosen approach adds zero cloud cost (no extra Claude call, no change to the 300/day cap), reuses a path that already exists and is already stub-tested, and keeps the cloud result authoritative — when the explanation lands it may also replace the fast translation with the cloud's own, better-contextualized one.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map.

Open consequence, ticketed separately: with the wait now split in two, M9's three-banner scheme (☁️ blue full / 📱 gray offline / ⚠️ orange declined) no longer maps onto the states the screen actually passes through — see [Reader result screen states after the split](09-reader-result-screen-states.md).
