# 16 — 單字本 list shows saved explanation content

**What to build:** extend the 單字本 list (`SavedTranslationRow` and related views) so a saved entry with explanation content (ticket 15) can be expanded to show its grammar/context/tone notes, while a fallback-only entry (those fields NULL) renders exactly as it does today — no broken or confusingly empty explanation section. No changes to the existing "jump back to source" (peek) behavior. Demoable by opening 單字本 and expanding both a full and a fallback-only saved entry.

**Blocked by:** 15

**Status:** ready-for-agent

- [ ] A 單字本 row with non-NULL explanation fields can be expanded to reveal grammar/context/tone notes
- [ ] A 單字本 row with NULL explanation fields (a fallback-only save, or a pre-existing M8-era saved translation) renders unchanged from today — no broken UI, no visible empty section implying missing data
- [ ] The existing "jump back to source" (peek) action is unaffected
- [ ] Build-verified on both a compact and a larger simulator layout for both row states (full and fallback-only)
