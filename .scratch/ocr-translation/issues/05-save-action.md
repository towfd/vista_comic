# 05 — "Save" action persists the translation to the backend

**What to build:** once a translation is shown (Ticket 04), a "Save" action calls `TranslationRepository` (Ticket 03) to persist the original text, translated text, target language, and source comic/chapter/page reference to the backend.

**Blocked by:** 03, 04

**Status:** resolved (commit `af08bd8` on `feat/ocr-translation-foundation`)

- [x] A "Save" action is available once a translation is showing (rendered inside `translationResultContent`'s `.loaded` case)
- [x] Tapping it calls `TranslationRepository.save` with the correct original text, translated text, target language, and source reference (`comicID`/`chapterID`/`pageNumber`, threaded down from `ReaderView`/`ReaderPage` the same way `saveProgress` already gets them)
- [x] Save failure shows a clear message (generic — `TranslationRepository.save` throws a plain `APIError`, not a distinguishable enum like `TranslationError`/`OCRRecognitionError`, so there was nothing to differentiate), not silent
- [x] Unit tests exercise this flow via a stub `TranslationRepository` — **verified by running**: 4/4 new tests pass (`SelectionSaveFlowTests`), plus the surrounding recognition/translation flow tests re-run clean alongside it
- [ ] Manual verification against the real backend — **not done**, consistent with tickets 02/03's established reasoning (no safe way to hit the live docker-compose stack from a worktree)

## Comments

This is the last of the five `ocr-translation` implementation tickets — the feature is functionally complete end-to-end (select → recognize → translate → save), modulo Ticket 06 (populating the 單字本 tab, which now has everything it needs: `TranslationRepository.list()` and the `EnvironmentValues.translationRepository` seam both exist).

"Save worked" confirmation UI: the Save button is replaced in place by a checkmark + "Saved" label — no toast, no auto-dismiss. Retranslating resets `saveState` to `nil` so a stale "Saved" indicator can't stick to a different translation result.

One coordination note: this ticket's own sub-agent session had an unexplained ~2-hour gap with zero file activity and no running process mid-implementation (not a crash, not a hung build — the agent's own status check confirmed no error, just no further tool call issued after 21:30). Resolved by the coordinator sending a direct status-check message, after which the agent resumed and finished normally. Flagging in case this recurs — it doesn't appear to be caused by anything in this ticket's own work.
