# 11 — The navigation bar and its count

**What to build:** The web gets its first shell: a bar across the top of the library, the comic page and practice, reading 書庫 · 練習, with the number of cards waiting beside 練習. The reader stays full-bleed without it. The count is fetched in the background and can fail without anyone noticing anything except its absence.

See the spec's *Navigation and routes*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** done (2026-10-12) — merged in #108; the browser checklist below is still the developer's to run

- [x] The bar appears on the library, the comic page and every practice route, and not on the reader
- [x] 書庫 and 練習 each lead to their page, and the current one is marked
- [x] The number beside 練習 is the same remaining figure the overview's three numbers add up to
- [x] When the deck or settings cannot be fetched for the count, the bar reads 練習 with no number, and the library shows no error and is not delayed
- [x] The library's own heading no longer duplicates the bar
- [x] Hand-off: a list for the developer covering the bar on each page, its absence in the reader, the count with the backend stopped, and one narrow and one wide window

## Comments

Implemented 2026-10-12. 119 unit tests pass; the type check and production build are clean. The page was not opened in a browser.

The bar and the overview now read one figure from the deck store, computed for the moment the deck was fetched, so they cannot disagree. The bar fetches the deck when it appears on a library or comic page — on first load, and again each time the reader is left, since the bar is not there during reading. Practice pages fetch for themselves. A count of zero shows no number.

One behaviour beyond the ticket's wording: the overview now shows its error whenever its own fetch fails, even if the bar had fetched a deck earlier, rather than presenting those older numbers as current. The bar, by contrast, keeps showing the last number it had.

**For the developer to check in the browser:**

- The bar — vista · 書庫 · 練習 — is on the library, a comic page and `/practice`, and absent in the reader, where the manga still fills the window.
- 書庫 is the brighter entry on the library and on a comic page; 練習 is on `/practice`.
- The number beside 練習 equals the overview's three numbers added together.
- Read a chapter, go back to the comic page: the bar is back and its number is fresh (a `/cards` request appears in the network panel).
- With everything done for the day, 練習 shows no number at all.
- Stop the backend and load the library with a cached page, or block `/cards` in the network panel: 練習 has no number, the library shows its covers and no error, and nothing waits on the blocked request.
- The library no longer has its own 書庫 heading under the bar.
- A narrow window (about 375 wide): the three entries and the number fit on one line.
- Tab to the bar with the keyboard: each entry takes focus and Enter follows it.
