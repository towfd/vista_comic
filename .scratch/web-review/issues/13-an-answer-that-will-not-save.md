# 13 — An answer that will not save

**What to build:** When a review cannot be saved, the session neither loses the answer nor moves on without it. The request is retried on its own a few times; if it still has not gone through, the feedback screen says the answer is unsaved and offers a retry, and there is no way past it. A card deleted on the phone meanwhile drops out quietly, and a lapsed sign-in is said plainly.

See the spec's *Answering and saving*.

**Blocked by:** 12 — A translate session that saves.

**Status:** ready-for-agent

- [ ] The API client has a request timeout, classified as the backend being unavailable
- [ ] An unreachable backend, a server error or a timeout is retried automatically a few times, backing off
- [ ] Every attempt carries the same token, the same moment of answering and the same local date
- [ ] With automatic attempts spent, the feedback screen reports the answer unsaved and offers a retry; the session cannot advance
- [ ] Nothing is written to browser storage
- [ ] A 404 removes the card from the session and offers the next question, with no retry
- [ ] An Access refusal tells the reader to sign in again, with no retry
- [ ] Any other refusal is shown as unsaved with the manual retry only
- [ ] Unit tests cover each of these in the session store, and the timeout in the client
- [ ] Hand-off: a list for the developer covering going offline mid-session and coming back, and deleting a card on the phone while it is on screen
