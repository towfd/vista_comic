Type: prototype
Blocked by: 06, 07
Status: resolved

# Result screen and fallback UX

## Question

What does the result screen look like when showing the merged translation+explanation (once ticket 06 fixes its shape), and how is the offline/cloud-failure fallback state (ticket 03's decision) communicated to the reader — does it look visually distinct from a full cloud explanation, or does the reader just see a plain translation with no indication anything degraded?

Also needs ticket 07's answer to know whether a "model declined to analyze this image" state needs its own distinct UI, alongside the network/API-error states already implied by the fallback design.

Resolve via `/prototype`.

## Answer

**Variant C — persistent status banner** — chosen over a progressive-disclosure layout and a tabbed (翻譯/解釋) layout.

Shape: a always-visible, high-contrast capsule banner at the very top of the result screen, before any content:

- ☁️ blue "雲端深度解釋" — full success, all four ticket 06 fields present (translation, grammar_notes, context_notes, tone_register)
- 📱 gray "離線模式・僅逐字翻譯" — ticket 03's offline/cloud-failure fallback to the on-device `Translator`; translation only
- ⚠️ orange "內容政策・僅提供翻譯" — ticket 07's "model declined" case; also falls back to the on-device `Translator` for a literal translation, but with visually distinct (orange, not gray) messaging so the reader isn't confused into thinking it's a generic connectivity problem

Below the banner: original text and translation always shown; grammar/context/tone sections shown in sequence only when present (success case only) — no tabs, no disclosure, everything visible at once once you scroll past the banner.

**Why this won over the other two drafted variants:** the banner is the first thing the reader sees, before any content — it answers "is this the full explanation or a degraded result" immediately, rather than requiring the reader to notice an absent disclosure section (variant A) or discover a disabled tab (variant B).

**Note for the eventual spec/implementation:** this was chosen via description only (no code written, no SwiftUI prototype built — this project's rule is no code changes before the implement phase); exact colors/copy/icons are implementation-time detail, not locked here.

## Comments

Resolved via `/prototype`-style description-only comparison (no code) on 2026-08-04, in the same conversation that created this map.
