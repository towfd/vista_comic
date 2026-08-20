# 02 — Free the jump-to-source route from 歷史紀錄

**What to build:** Nothing new. Move the navigation that jumps from a saved line back to the page it came from out of `Features/History/`, so it survives that folder being deleted.

**This ticket exists because of the mistake it prevents.** 歷史紀錄 is removed in ticket 03, and the peek route lives in `Features/History/ComprehensionSummary.swift`. Deleting the folder wholesale and re-implementing the jump in the new screen is the easy path, and it would trade a working piece of navigation — one that already handles a comic that has left the library, and already avoids writing reading progress — for a fresh set of bugs in something the reader had working yesterday.

Separated from ticket 03 so the diff there is a screen being added and a screen being removed, rather than those plus a refactor whose regressions would be invisible among them.

**Behaviour must not change at all.** Same route, same peek semantics, same handling of a source that no longer exists. If this ticket is visible to the reader in any way, it went wrong.

**Blocked by:** nothing.

**Status:** done — `SourceReference` extracted with its four assertions re-asserted against the new type; shipped in `43ae9f0`, merged in PR [#81](https://github.com/towfd/vista_comic/pull/81). Invisible by design, so no device pass applied.

- [x] The peek route and its supporting types live outside `Features/History/`
- [x] 歷史紀錄 still uses it, unchanged, and still behaves identically
- [x] Jumping to a page still does **not** write reading progress
- [x] A source comic that is no longer in the library still degrades the same way
- [x] Existing tests covering the route move with it and still pass, without being rewritten to fit
- [x] No behaviour change is introduced anywhere; the diff is a move plus whatever the move requires
