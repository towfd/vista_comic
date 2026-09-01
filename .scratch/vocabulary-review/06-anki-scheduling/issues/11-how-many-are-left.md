Status: done — device-verified by the repo owner, 2026-09-01

# 11 — How many are left

**What to build:** A running count of the cards a scheduled session still has to get through, shown beside `N answered` in the session header.

A follow-up raised by the repo owner after using ticket 04's session. "Runs until nothing is left" is the right ending, and it is also the reason the reader cannot tell whether they are two cards from the end or twenty — a session with no visible length is one you stop out of doubt rather than because you are done.

## What the number is

**The cards the queue would still offer, if the reader kept answering right now.** Mirroring `nextCard` exactly, that is:

1. Cards past `new` whose `dueAt` has passed, plus
2. what is left of today's new quota, capped by how many `new` cards the deck actually holds, plus
3. learning cards due inside `learnAheadWindow` and not already counted in (1).

The third line is what makes the figure honest rather than tidy: a card on a five-minute step *will* be asked again in this session, so leaving it out would show `0` while the session kept handing out questions.

**The invariant this is built against, and the test that pins it:** the count is `0` if and only if `nextCard` returns a failure, for the same deck, settings, clock and day. Anything else is two implementations of "finished" disagreeing, which is how the three-step day's "still says New" bug happened.

**Not a question count.** A wrong answer sends a card back to the start of the learning steps, so the number of *questions* left is unknowable — that is settled and is not being reopened. This counts cards.

## What it will honestly do

**It will not tick down once per answer, and that must not be treated as a bug.** Answer a learning card correctly and it moves from a 5-minute step to a 7-minute one: still inside the learn-ahead window, still counted, because it is still coming. The figure falls when a card graduates onto the interval table in days, and when the day's new quota is spent.

That is the truth about the session, and it is the same principle the schedule summary on the row was built on — the reader was shown an adjective that did not move and read it as a verdict on themselves. So:

- Label it as cards, not as progress. `12 left` beside `4 answered`.
- **No progress bar, no percentage, no ring.** The count never rises inside a session — introducing a new card moves it from the quota to the learning pool and nets to zero — but it stalls, for several answers at a time, whenever the reader is working through the learning steps. A bar that freezes reads as a failure to make progress. A number that freezes reads as three cards not learned yet, which is what it is.
- If the device pass finds the figure sits still long enough to feel broken, the fix to try first is showing what it is waiting on ("3 coming back soon"), not switching to a count that lies.

## Where it goes, and where it does not

- **Scheduled sessions only.** 永無止盡的訓練 has no remaining anything — that is the mode's entire premise — and a count there would be a pool size dressed up as an ending. The training header keeps `N answered` alone.
- The session header already carries `N answered` on the left and the current card's schedule on the right. The new figure joins that row; it does not get a bar of its own above the prompt, which is the question's space.
- **The start screen is not part of this ticket.** `cards due` and `new today` are already there and already correct.

## Where the code goes

`remainingCards(from:settings:now:today:)` — a pure function in `PracticeQueue.swift`, next to `nextCard`, over the same arguments and reading no clock of its own. It is derived from the session's own `deck`, which every answer already updates from the response, so it is right with no network and moves without a refetch.

## Blocked by

Nothing. Tickets 03 and 04 shipped; this reads the queue they built.

## Acceptance criteria

- [x] A scheduled session shows the remaining card count in the header, beside the answered count
- [x] 永無止盡的訓練 does not show it
- [x] The count comes from a pure function in `PracticeQueue.swift` taking deck, settings, clock and day
- [x] Unit test: the count is `0` exactly when `nextCard` fails, over an empty deck, a finished day, a deck with only future review cards, and a deck with a learning card due inside the learn-ahead window
- [x] Unit test: a `new` card counts only while the day's quota has room, and the quota cap never counts more new cards than the deck holds
- [x] Unit test: a learning card due inside the learn-ahead window is counted exactly once, not twice via rule (1)
- [x] Unit test: introducing a new card leaves the count unchanged — it moves from the quota to the learning pool
- [x] Unit test: a card answered wrong stays counted, and one that graduates onto the interval table leaves the count
- [x] The figure updates from the in-memory deck after each answer, with no refetch and with no network
- [x] No progress bar, percentage, or ring is added
- [x] The closing screen is unchanged — it already distinguishes an empty deck from a finished day
- [x] No XCUITest is written, built, or run — the device checklist is the deliverable

## File boundary

- `vista_comic/vista_comic/Features/Study/PracticeQueue.swift`
- `vista_comic/vista_comic/Features/Study/PracticeView.swift` — the header row only
- `vista_comic/vista_comicTests/`

Nothing in `Scheduler.swift` or on the backend. This ticket reads the queue; it does not change what the queue does.

Everything above is ticked: the unit-tested half by the suite, the visual half by the repo
owner's device pass on 2026-09-01, which passed with no changes asked for.

## What was built

- `remainingCards(from:settings:now:today:)` in `PracticeQueue.swift`, immediately after
  `nextCard` and over the same four arguments, reading no clock of its own.
- One line in the session header, behind `if mode == .scheduled`, with the identifier
  `cardsRemaining`.

**One correction made while building, and it is in the ticket above.** The draft claimed the
count could rise — answer a review card wrong, gain one. It cannot: a lapsed card was already
counted as due, and it stays counted as a learning card inside the window. Introducing a new card
is the same story in reverse, moving from the quota to the learning pool and netting to zero. So
the figure never rises and never overshoots; it **stalls**, sometimes for several answers, while
the reader works through the learning steps. That is a different thing to warn about, and it is
the real argument against a progress bar.

## Verification

`xcodebuild test -only-testing:vista_comicTests` on iPhone 16 (18.1): **533 tests, 0 failures**,
2 skipped, about 165 seconds end to end. Seven new tests in `PracticeQueueTests.swift`
(`How many are left`).

The one that matters is `zeroMeansFinished`: seven decks, and for each of them the count is zero
if and only if `nextCard` fails. It is written as a loop over decks rather than as seven tests on
purpose — the invariant is the assertion, and a new queue rule should be added to that array.

Not verified here, by rule: everything visual. No XCUITest was written, built, or run.

## Device checklist for the repo owner

1. Start **複習卡片**. The header reads `0 answered` and `N left`, and `N` includes the card on
   screen.
2. Answer through to the end. The count reaches **zero at the same moment** the closing screen
   appears — never a session that keeps asking at `0 left`, never a closing screen at `3 left`.
3. Answer a card **wrong**. The count does not drop, and does not rise either. It is the same
   number, because that card is still coming back.
4. Answer one **right** through to graduation. The count drops by one.
5. Start **永無止盡的訓練**. There is **no** left-count, only `N answered`.
6. Stop mid-session and start a new one. The count is right for what is actually left, not for
   what the day started with.
7. **Airplane mode**: the count still moves after every answer, with no network.
8. **Compact and larger phone.** On an iPhone SE the header is three items on one row — check
   that `12 answered`, `120 left` and a long schedule label do not collide or truncate.
9. Both appearances, since the row is caption-grey on the screen background.
