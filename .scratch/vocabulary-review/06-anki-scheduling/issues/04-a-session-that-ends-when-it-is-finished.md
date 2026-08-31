Status: implemented on branch `feat/anki-session`, 2026-08-31

# 04 — 複習卡片: a session that ends when it is finished

**What to build:** The practice screen on top of the engine — the first ticket where the reader
can see any of this.

The 練習 tab offers two entrances. This one runs the schedule: it asks until the queue is empty,
then says so. No progress bar counting to ten, because the total is not known in advance and a
bar that grows while you answer is worse than none.

Each question shows the card's state and next due time in the readout added in #86, now reading
`學習中 2/3 · 7 分鐘後` rather than a familiarity word.

**Stopping is free and must look free.** A stop control is visible throughout, and leaving mid-way
keeps every card exactly where it is. The empty state — nothing due, quota spent — is the reward
for finishing and should read as an ending rather than as an error.

`RoundView`'s per-question judging and feedback are kept as they are; what changes is what feeds
it and what ends it.

**Blocked by:** 03.

- [ ] A wrong answer brings the card back later in the same sitting
- [ ] Answering a card correctly three times in a row graduates it, and the readout says so
- [ ] Force-quitting mid-session and reopening resumes with the same cards in the same states
- [ ] The session ends by itself and says the day is done
- [ ] Stopping mid-session loses nothing and costs nothing
- [ ] Compact and large phone layouts both hold the question, the readout and the stop control
- [ ] Empty deck, deck of one card, and network failure mid-session all have a defined screen

## What was built

`PracticeView` rewritten around the queue: two entrances, no fixed length, a stop
control in the toolbar throughout, and a closing screen that distinguishes "no
words yet" from "nothing left for today".

**Shipped together with ticket 03, in one branch and two commits.** Ticket 03
deletes `makeRound`, which `PracticeView` was built on, so leaving the two apart
would have meant writing an adapter for one commit and deleting it in the next.
The verification split still holds: everything in 03 is provable by test, and
everything worth looking at is here.

**The question header no longer shows an adjective.** It reads
`Learning 2/3 · in 7 min` or `21 days · in 3 days`, which is `Familiarity`'s
replacement in the one place a reader is guaranteed to see it. The rest of that
swap — 單字庫's rows, and deleting `Familiarity` — is ticket 08.

**A wrong answer no longer requeues the card by hand.** The scheduler already sent
it to the first learning step, so it comes back on its own a few minutes later.
That is the same mechanism that made 錯題區 unnecessary, showing up in the view
layer as code that could be deleted.
