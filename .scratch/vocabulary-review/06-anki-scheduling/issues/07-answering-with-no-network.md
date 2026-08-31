Status: ready-for-agent

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
