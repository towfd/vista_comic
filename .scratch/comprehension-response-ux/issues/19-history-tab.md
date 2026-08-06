# 19 — 歷史紀錄 replaces 單字本

**What to build:** The reader gets a History tab where 單字本 used to be, filling automatically with everything they translate, badged with the count of explanations that have arrived and not yet been read. Opening a record shows the whole thing and clears its badge.

Unlike 單字本 — a short list of things deliberately kept — this fills up on its own, so scanning matters. A flat, newest-first list of compact two-line rows: an unread dot and the source text, then a status glyph, comic and chapter, and relative time. Tapping pushes a detail screen that reuses the result screen's vocabulary rather than inventing a second one.

Grouping by comic and chapter was considered and rejected: a reader working through one long series collapses into a single enormous section, and a just-arrived explanation stops being reliably at the top — which is where the thing the badge points at wants to be.

Actions on records — retry, delete, jump back to the source page — are the next ticket. This one delivers browsing and reading.

**Blocked by:** 18 (the shared explanation section this detail screen renders).

**Status:** ready-for-agent

- [ ] The 單字本 tab slot now holds 歷史紀錄, with the tab label and icon updated and the string catalog adjusted.
- [ ] The list shows compact two-line rows, newest first, flat and ungrouped, using the comic and chapter **titles** from the API — never the raw ids.
- [ ] Each row's status line distinguishes arrived, being produced, declined and failed.
- [ ] ~~Rows show the cloud translation where present, the on-device one otherwise.~~ **Superseded during implementation.** This contradicted the Variant B mockup this ticket was drawn from, which puts the translation on the detail screen and keeps rows to two lines. Resolved in favour of the mockup: a third line costs roughly a third of the records visible per screen, on a list whose whole job is scanning. The intent is carried instead by the row's status glyph, which is a cloud exactly when a cloud translation exists — so the row still says *that* the cloud version is there. The **detail screen** shows the cloud translation where present, the on-device one otherwise (see the AC below).
- [ ] The tab carries a badge counting unread records, computed client-side from the fetched list — there is no count endpoint and no shared client store.
- [ ] The list refreshes when the app returns to the foreground and when the tab appears.
- [ ] Only a successfully-arrived explanation is ever unread: never the fast translation, never a failure, and never one the reader already watched land on the result screen.
- [ ] Tapping a row pushes a detail screen showing the translation with its provenance chip and the shared explanation section in whichever state applies.
- [ ] **Opening the detail marks that record read**, clearing exactly that one from the badge — visiting the tab clears nothing.
- [ ] XCUITest code for the tab and detail is written and build-verified; running it is handed off.
- [ ] One compact and one larger phone layout both checked.
