# 05 — "Save" action persists the translation to the backend

**What to build:** once a translation is shown (Ticket 04), a "Save" action calls `TranslationRepository` (Ticket 03) to persist the original text, translated text, target language, and source comic/chapter/page reference to the backend.

**Blocked by:** 03, 04

**Status:** ready-for-agent

- [ ] A "Save" action is available once a translation is showing
- [ ] Tapping it calls `TranslationRepository`'s save method with the correct original text, translated text, target language, and source reference
- [ ] Save failure shows a clear message, not a silent failure
- [ ] Unit tests exercise this flow via a stub `TranslationRepository`, independent of the real backend
- [ ] Manual verification (environment permitting): save a real translation, confirm the row exists in the backend afterward
