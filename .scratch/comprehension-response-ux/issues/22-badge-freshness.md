# 22 — The badge has to learn while the reader is elsewhere

**What to build:** The 歷史紀錄 badge appears when an explanation lands, without the reader opening the tab.

**This reverses a locked decision in this spec.** The 歷史紀錄 section says the badge is "refreshed when the app returns to the foreground and when the tab appears", with "no shared client store: each screen fetches for itself". Shipped, that produces a badge that can only learn something arrived at the exact moments the reader no longer needs telling. Translate, dismiss the sheet, keep reading: nothing fetches the list, `unreadCount` stays 0, and the badge first appears on the frame *after* the reader has already opened the tab it was supposed to send them to.

That contradicts the user story the badge exists for — "so that I know when there is something new to go and read" (12). The refresh policy was the wrong half of the pair to lock: the per-screen-fetch rule is sound for the *list*, which only matters when it is on screen, and wrong for the *badge*, whose whole job is to speak while the reader is somewhere else.

The counting rule is not at fault and does not change. A reader who dismisses the sheet cancels `awaitExplanation`, so nothing marks the record read and it is correctly unread — it was simply never counted again.

**What changes:** badge ownership moves out of `HistoryView` up to the tab shell, and the shell keeps it current two ways. It refreshes once on launch and on return to the foreground, which catches anything that finished while the app was dead or backgrounded. And it watches a record it knows to be in flight — handed to it when the reader translates — polling until the backend reaches a terminal status, then recounting. Nothing in flight means no polling at all: the mechanism is silent on a day the reader never translates.

Each half covers the other's hole. Watching alone loses everything enqueued before a relaunch; refreshing alone either misses the arrival by minutes or polls all day to avoid it.

**The shared store the spec rejected is now unavoidable** and should be as small as the job: a count, a way to recount from a list a screen already has, and a way to watch one record. `HistoryView` hands over the list it just fetched rather than triggering a second fetch, so the tab that is on screen costs nothing extra. This is the codebase's first `@Observable`, which is worth stating plainly rather than smuggling in.

**Blocked by:** nothing. 19 and 20 are merged; 21 is in review and does not touch this.

**Status:** ready-for-agent

- [ ] Translating and immediately dismissing the sheet makes the badge appear when the explanation lands, with the reader still in 書庫 and never having opened the tab.
- [ ] An explanation the reader watches land on the result screen is marked read there and never badges.
- [ ] The badge is correct on a cold launch, counting whatever finished while the app was not running.
- [ ] Returning from the background refreshes it.
- [ ] Opening a record clears exactly that one from the count, and deleting a record drops it, both without a second network fetch.
- [ ] Polling stops once the watched record reaches a terminal status, and never starts when nothing is in flight.
- [ ] The watch survives the sheet being dismissed — it is owned by the shell, not by the view that started it.
- [ ] The badge's poll never marks anything read; only the reader watching it land does that.
- [ ] The spec's 歷史紀錄 section is amended to record this reversal and why, rather than being left contradicting the shipped code.
- [ ] Unit tests cover the counting and the watch's stop condition against a stub repository, with no sleeps.
- [ ] XCUITest code is written and build-verified; running it is handed off.
