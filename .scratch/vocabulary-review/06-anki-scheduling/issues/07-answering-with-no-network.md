Status: implemented on branch `feat/anki-offline`, 2026-08-31

# 07 — Answering with no network

**What to build:** The fourth member of the `PendingCardStore` family, so a session works in
airplane mode.

Every answer is appended to a local durable queue **the moment it is given** — not at the end of
the session. An answer is an event that cannot be reconstructed, and a session-end save would
lose a whole sitting to a crash while making leaving the app feel expensive.

The local deck snapshot is updated with the same scheduler the backend runs, so the queue keeps
building offline. On reconnect the queue flushes in order, carrying each answer's original
`answeredAt`, and **the backend's returned state overwrites the local one**. Nothing needs to
detect a conflict: the two sides run the same pure function over the same answers, and
`uq_card_review_client_token` makes a resubmission harmless.

The scheduler must exist in Swift for this, mirroring the Python. That duplication is deliberate
and is the price of offline practice; pin it with tests that assert the same transition table as
ticket 01, so the two cannot drift silently.

**Blocked by:** 04.

- [ ] A full session in airplane mode schedules cards correctly and shows the same readouts
- [ ] Answers survive a force-quit before any flush
- [ ] Reconnecting flushes every answer in order, with its original timestamp
- [ ] After a flush the local and server states agree
- [ ] Flushing twice changes nothing
- [ ] A card deleted on the server while offline drops its queued answers instead of retrying
- [ ] Swift and Python transition tests assert the same table

## What was built

`PendingAnswerStore` (the fourth queue of this shape), `replaying(_:over:)`, and
`Features/Study/Scheduler.swift` — the transition table in Swift.

**The queue is also read back, which is new.** The other three queues only send;
this one is what the session is built from while offline. `knownCards()` is now
the last good snapshot with the queued answers replayed over it, so a card
answered wrong five minutes ago is back in the learning steps and the queue
offers it again — without a server ever hearing about it.

That works because scheduling is a pure function of a card's state and the
answers against it, so replaying lands where the backend will land when the
queue reaches it. **Nothing is reconciled**: the server recomputes from the same
answers and its result replaces the local one.

**The second implementation is the cost, and it is paid down deliberately.**
`SchedulerParityTests` asserts the same cases as `backend/tests/test_scheduler.py`
with the same numbers, so a change to one that is not made to the other fails a
test rather than a reader's schedule. The two differ in exactly one place, noted
in both: given an unusable step list the backend raises (a route can answer 422)
and the app falls back to the defaults (there is nobody to tell, and refusing to
schedule would strand the card).

**Stage 4's reason for refusing to queue answers is gone.** It refused because
the ladder's once-a-day rule made arrival order load-bearing and a queue could
not promise it. Order still matters — each answer's effect depends on where the
previous one left the card — but the order that matters is when the reader
*answered*, which `answeredAt` records and a flush cannot change.
