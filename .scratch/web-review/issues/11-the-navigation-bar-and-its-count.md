# 11 — The navigation bar and its count

**What to build:** The web gets its first shell: a bar across the top of the library, the comic page and practice, reading 書庫 · 練習, with the number of cards waiting beside 練習. The reader stays full-bleed without it. The count is fetched in the background and can fail without anyone noticing anything except its absence.

See the spec's *Navigation and routes*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** ready-for-agent

- [ ] The bar appears on the library, the comic page and every practice route, and not on the reader
- [ ] 書庫 and 練習 each lead to their page, and the current one is marked
- [ ] The number beside 練習 is the same remaining figure the overview's three numbers add up to
- [ ] When the deck or settings cannot be fetched for the count, the bar reads 練習 with no number, and the library shows no error and is not delayed
- [ ] The library's own heading no longer duplicates the bar
- [ ] Hand-off: a list for the developer covering the bar on each page, its absence in the reader, the count with the backend stopped, and one narrow and one wide window
