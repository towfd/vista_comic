# 05 — 已下載: review what is on the device, and delete it

**What to build:** One place that answers "what can I read without a connection, and what is it costing me" — and lets the reader act on the answer. Downloaded chapters are listed grouped by comic, each showing its size and state, with the allowance in use shown at the top. A chapter can be deleted individually, and everything can be cleared at once.

It is also the **offline entry point**. Opening a chapter from here goes straight into the Reader, so a reader on a plane has a screen that is guaranteed to be about things that work, rather than browsing 書庫 and finding out one chapter at a time.

Deletion is what makes ticket 04's eviction tolerable. Until this exists, the reader's only influence over what is on the device is the order in which they downloaded things; after it, first-in-first-out is a default they can override — they can free the slot they want freed instead of the one the clock chose.

Deleting everything is irreversible and asks for confirmation first, following the destructive-action pattern this app already uses for removing a saved record. Deleting one chapter is a smaller loss and needs no dialog: it removes the chapter's files and record and frees its slot immediately.

**Blocked by:** 01 — Download a chapter to the device; 04 — Cap downloads at 20 chapters, evicting the oldest first.

**Status:** ready-for-agent

- [ ] A 已下載 surface lists every downloaded chapter, grouped by comic
- [ ] Each entry shows the chapter's identity, its size, and whether it is complete or still downloading
- [ ] The number of downloads in use against the cap is shown
- [ ] A chapter can be deleted from the list, removing its files and record and freeing its slot immediately
- [ ] Everything can be cleared in one action, behind a confirmation, since it is irreversible
- [ ] Opening an entry goes directly into the Reader at that chapter
- [ ] The screen works with no connection, since that is when it matters most
- [ ] The list stays correct after an eviction, so a chapter removed by the cap disappears from it
- [ ] An empty state explains that nothing has been downloaded yet
- [ ] Deleting a chapter does not disturb queued reading positions
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout
