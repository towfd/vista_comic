# 06 — Download several chapters in one action

**What to build:** A reader following a serial wants the next few chapters before they leave, not one tap at a time. From the chapter list they enter a selection mode, tick the chapters they want, and download them together.

This is the difference between the feature being usable and being tedious at the size the library has actually reached — past 300 chapters, preparing for a journey by tapping individual rows is the kind of chore that stops a feature from being used at all.

The chapters queue and download one after another under the same rules as a single download: foreground only, page-level resume, four page fetches at once, and each chapter completing only when every page is present. Progress is legible per chapter rather than as one aggregate bar, so an interrupted batch shows exactly which chapters made it.

**The interaction with the cap is the risk worth naming.** A batch admitted at the cap evicts exactly as many chapters as it admits — five in means five out. That semantic belongs to ticket 04 and is tested there; what this ticket must not do is find a way around it, most obviously by admitting the whole batch at once as though it were a single unit. Selecting more chapters than the cap allows is the case to think through: the reader should not be able to issue a batch that would evict chapters it is itself about to add.

**Blocked by:** 01 — Download a chapter to the device; 04 — Cap downloads at 20 chapters, evicting the oldest first.

**Status:** ready-for-agent

- [ ] The chapter list offers a selection mode in which several chapters can be ticked
- [ ] Confirming downloads every selected chapter, queued under the same rules as a single download
- [ ] Each chapter shows its own progress, and completes independently of the others
- [ ] Leaving selection mode without confirming downloads nothing
- [ ] Already-downloaded chapters cannot be selected for download again
- [ ] A batch admitted at the cap evicts exactly as many chapters as it admits
- [ ] A batch cannot evict chapters that the same batch is in the process of adding
- [ ] A batch larger than the cap allows is handled sensibly rather than silently thrashing
- [ ] An interrupted batch resumes without re-fetching what already arrived, and shows clearly which chapters completed
- [ ] Entering and leaving selection mode does not disturb normal chapter-list navigation
- [ ] No XCUITest is written; a device checklist is handed to the repo owner, covering both a compact-phone and a larger-phone layout
