# 17 — Manual "request a stronger explanation" action

**What to build:** a secondary action on the result screen (exact placement/wording left to the implementer, per the spec) that re-issues the `Comprehender` call with the Sonnet-tier override (already supported by ticket 13's `APIComprehender` and ticket 11's backend contract), replacing the currently-shown result with the new one once it returns. Only meaningful after a successful (blue-banner) result — a fallback state has no "explanation" to upgrade. Demoable by translating, then tapping the upgrade action, and observing the result refresh with (typically) a deeper explanation.

**Blocked by:** 14

**Status:** ready-for-agent

- [ ] A secondary action is available once a successful (blue-banner) comprehension result is showing
- [ ] Tapping it re-calls `Comprehender` with the Sonnet-tier override and replaces the displayed result on success
- [ ] The action is not shown (or is disabled) in the fallback (gray/orange banner) states, since there's no explanation to upgrade
- [ ] A failure on the upgraded call leaves the original (Haiku-tier) result visible rather than clearing it — the reader never ends up with less than they had before tapping upgrade
- [ ] Unit tests exercise this action with a stub `Comprehender`, covering both a successful upgrade and a failed upgrade attempt
