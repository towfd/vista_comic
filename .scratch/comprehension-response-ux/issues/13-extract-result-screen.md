# 13 — Extract the selection result screen out of the reader file

**What to build:** No user-visible change at all. The OCR/translate result sheet and the free functions it calls currently live inside the same file as the reader, page view and progress-reporting logic — a file approaching sixteen hundred lines. Three later tickets rework that screen heavily. Move it, unchanged, into its own feature file first so those tickets are edits to a focused file rather than surgery inside a large one.

This is a prefactor: make the change easy, then make the easy change. It is deliberately behaviour-preserving so it can be reviewed as a pure move.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The result sheet view and the selection free functions it calls live in their own file(s) under the reader feature, with the reader file retaining only the reader, page and progress code.
- [ ] No behaviour changes: no renamed types, no changed signatures, no altered view bodies beyond what the move mechanically requires.
- [ ] Existing selection tests pass untouched — if a test needed editing, the move was not behaviour-preserving.
- [ ] The app builds, and the reader → select → recognise → translate → save path still works end to end in the simulator.
- [ ] Any preview providers that moved still render.
