# 04 — Stop the prefetch suite failing on a busy machine

**What to build:** `PageImageCacheTests` passes because the cache is correct, not because the machine happened to be idle.

Three of its tests were failing intermittently — a different one each time, which is what made it look like a mystery rather than a bug. Captured with `-resultBundlePath` pointed somewhere writable (the default location fails with `mkstemp: No such file or directory` in this environment, which is why the assertions were invisible for so long):

- `noMoreThanFourFetchesRunAtOnce` — `(peakConcurrentLoads → 3) == 4`
- `aPageTheReaderLandsOnIsFetchedAheadOfQueuedPrefetches` — `(order[4] → …/priority/4) == urls[5]`
- `aFailedURLIsNotReRequestedByASubsequentWindowReconcile` — `(requests.count → 7) == 6`

**The third one is the root cause, and it is not really about that test.** The prefetch window is fire-and-forget by design: a test can return while the coordinator is still working through the pages it asked for, and those requests are then recorded against whichever test runs next. Almost every assertion in this suite is an exact count, so one straggler reads as a bug in the cache — in a different test each time.

The other two are assertions that describe a scheduling accident rather than a guarantee. The cache promises *at most* four fetches at once; observing exactly four at one instant additionally requires the fourth to start before any of the first three finishes, which a busy machine will not always allow. Likewise the priority test served every response after 0.4s and hoped the explicit ask arrived first.

**The fix is to take the clock out of it.** The stub gains a hold: responses are parked until the test releases them, one at a time or all at once. A delay makes fetches *probably* overlap; holding makes them certainly overlap. And every test now waits for the previous one's work to finish before clearing the stub.

**Blocked by:** None.

**Status:** implemented on branch `fix/prefetch-test-flakes`, 2026-08-18 — **not executed**, see below.

- [x] The failures are captured rather than guessed at, with their real assertions
- [x] Concurrency is asserted as the guarantee ("no more than four"), proven by holding four open at once
- [x] Priority is asserted by freeing exactly one slot, so "which went next" is a fact rather than a scheduler's choice
- [x] Work left running by one test cannot be recorded against the next
- [x] No assertion is weakened to make a failure go away
- [ ] The suite is run repeatedly and passes — **blocked**, see below

## What was changed

- `CacheStubURLProtocol` gains `hold()`, `releaseOne()`, `release()` and `loadsInFlight`. Parked responses are dropped by `reset()`, so nothing leaks across tests.
- `noMoreThanFourFetchesRunAtOnce` holds every response, waits until four are in flight, asserts the peak is four, then releases and asserts it never moved. The guarantee is now what is measured.
- `aPageTheReaderLandsOnIsFetchedAheadOfQueuedPrefetches` holds four open, starts the explicit ask, then frees **exactly one** slot. Releasing everything at once would let two resumed fetches record their requests in whichever order the scheduler picked; releasing one makes the answer a fact. It then drains its own window before returning.
- `freshStub()` replaces the direct `CacheStubURLProtocol.reset()` in all 26 tests: wait for quiet, settle, check again, then reset. Quiet is checked twice because a queued fetch starts the moment a slot is freed, so a single reading of zero can be the gap between two of them.

## Verification — not done, and why

The concurrency fix was run and passed. The priority fix was run and is what surfaced the leakage. **The `freshStub()` change has never been executed.**

While hunting this, several test runs were killed mid-flight, and the simulator test host then wedged: builds complete normally, but `xcodebuild test` hangs before "Testing started" — two different simulators, ten minutes each, zero tests run, unchanged by shutting every simulator down and rebooting the target. The repo owner chose to proceed without a local run rather than spend more time on the environment.

**So this branch is unverified.** The changes are mechanical and the reasoning is recorded above, but the suite must be run — `⌘U` in Xcode is enough — before this is trusted.
