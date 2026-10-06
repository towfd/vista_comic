# 03 — Next-chapter button at the end of a chapter

**What to build:** Below 「本話完」, a primary button 「下一話 · 第 N 話」 that opens the following chapter from its top. The existing 「回到章節列表」 link stays beneath it. Rules are in the spec's "Next-chapter button" section:

- **Next comes from the comic's chapter list**: the comics store's cached `GET /comics/{comicId}` if present, otherwise fetched in the background without blocking the pages. Next = the entry after the current chapter id.
- **Hidden** on the last chapter, when the current id is not in the list, and until the list has arrived.
- **Opens at the top**, ignoring the next chapter's `lastReadPage` (as iOS auto-advance), through ticket 02's top override. The flag rides in `history.state` and is **cleared once applied**, so a reload resumes from the saved position. The gate still protects the next chapter's saved position until the reader scrolls.
- **`router.replace`**, so browser back after 5 → 6 → 7 returns to the chapter list.
- **Pressing it flushes progress** (ticket 02's flush) — with 「本話完」 visible that is `pageCount`.

**Blocked by:** 02

**Status:** ready

- [ ] Pure `nextChapter(chapters, currentId)` with unit tests: middle → following; last → none; unknown id → none
- [ ] Button renders below 「本話完」 with the next chapter's number; hidden in the three cases above
- [ ] Reader loads the comic detail in the background when the store lacks it; pages are never blocked on it
- [ ] Next chapter opens at its top even with a saved position; reload mid-chapter resumes instead of restarting
- [ ] `router.replace` navigation; progress flushed before leaving
- [ ] `vue-tsc` clean, vitest green

## Browser checklist for the developer

- [ ] End of a chapter → button names the right chapter; pressing it opens that chapter at its top, even one read halfway on the phone
- [ ] The finished chapter shows 已讀 afterwards
- [ ] Last chapter → no button
- [ ] Two hops, then browser back → chapter list
- [ ] Open a reader URL directly (fresh tab) → the button still appears once the list arrives
- [ ] After a hop, scroll a little, reload → resumes there, not at the top
