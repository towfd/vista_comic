Type: grilling
Status: resolved

# An answer that cannot be posted

## Question

The web has no offline queue and takes its schedule from the response to `POST /cards/{id}/reviews`. What does the session do when that request fails or is slow?

Whether the next question waits for the response or is shown at once; whether a failed answer is retried, held, or dropped; and what the reader is told. Each question carries a token so a resubmission cannot count twice — the retry is safe, the open matter is what the session does meanwhile, given that where a card goes next in the queue depends on the schedule that has not come back.

## Answer

**The verdict is shown at once; the next question waits for the response; a failure holds the session on the question it failed on until the answer is saved.**

The two halves of an answer come apart. Whether it was right is judged in the browser and needs nothing from the server, so the verdict and the card's own text appear the moment Enter is pressed. Where the card goes next is the server's to say, so the request is sent at that same moment and **the next question is not offered until its response has arrived.** In the ordinary case the reader is still reading the feedback when it lands and never sees a wait; if they press on first, the control shows that it is waiting.

This is the phone's hazard closed by construction rather than guarded against: the queue is only ever computed from schedules the server has actually returned, so no card can be offered again while its own answer is in flight. Letting the reader go on at once with the unanswered card held out of the queue was offered and declined — it buys smoothness at the price of a count of cards remaining, and a "finished", that are both wrong until every response is in.

**On failure** — no connection, a 5xx, a timeout — the request is retried automatically a few times, and if it still has not gone through the feedback screen says the answer is not yet saved and offers a retry. There is no way forward past it.

- Every retry carries the **same** `clientToken`, so an attempt that reached the server and lost only its response cannot count twice.
- Every retry carries the **same** `answeredAt` and `localDate`, fixed when the answer was given — a learning step is counted from when the reader answered, not from when the network came back.
- Nothing is dropped silently, and nothing is written to browser storage. **Closing the tab loses the one unsaved answer.** That is the stated cost: keeping it would be an offline queue, which is out of scope. A way to abandon the answer and move on was also offered and declined.

Two failures are not retried, because retrying cannot fix them:

- **404 — the card no longer exists**, deleted from the phone while the tab was open. The card leaves the session and the next question is offered.
- **The Cloudflare Access session has lapsed**, so the request comes back as a sign-in page rather than JSON. The reader is told to sign in again; the answer in hand goes with the reload.

Not decided here, and left to the spec: how many automatic attempts, how far apart, and how long before a request counts as timed out. The web's API client has none of the three today.

## Comments

Per [What the engine must reproduce](01-what-the-engine-must-reproduce.md): the phone never waits — it moves the card with its local scheduler and posts in the background. The web has no local scheduler, so this is not a detail it can copy; a queue rebuilt before the response lands offers the same card again.

Resolved 2026-10-12 via `/grilling`. Whether the response's scheduling block is patched onto the one card or the whole deck is fetched again belongs to [The queue under two clients](03-the-queue-under-two-clients.md). The 404 and Access cases were filled in by the agent as consequences rather than put to the developer as choices.
