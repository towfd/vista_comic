# 13 — An answer that will not save

**What to build:** When a review cannot be saved, the session neither loses the answer nor moves on without it. The request is retried on its own a few times; if it still has not gone through, the feedback screen says the answer is unsaved and offers a retry, and there is no way past it. A card deleted on the phone meanwhile drops out quietly, and a lapsed sign-in is said plainly.

See the spec's *Answering and saving*.

**Blocked by:** 12 — A translate session that saves.

**Status:** done (2026-10-12) — merged in #110; the browser checklist below is still the developer's to run

- [x] The API client has a request timeout, classified as the backend being unavailable
- [x] An unreachable backend, a server error or a timeout is retried automatically a few times, backing off
- [x] Every attempt carries the same token, the same moment of answering and the same local date
- [x] With automatic attempts spent, the feedback screen reports the answer unsaved and offers a retry; the session cannot advance
- [x] Nothing is written to browser storage
- [x] A 404 removes the card from the session and offers the next question, with no retry
- [x] An Access refusal tells the reader to sign in again, with no retry
- [x] Any other refusal is shown as unsaved with the manual retry only
- [x] Unit tests cover each of these in the session store, and the timeout in the client
- [x] Hand-off: a list for the developer covering going offline mid-session and coming back, and deleting a card on the phone while it is on screen

## Comments

Implemented 2026-10-12. 181 unit tests pass; the type check and production build are clean. The page was not opened in a browser.

The numbers chosen: a request times out after 10 seconds; an unreachable backend is retried after 1, 2 and 4 seconds — four attempts in all — before the answer is reported unsaved. With every attempt timing out, that is about 47 seconds of 儲存中 before the message appears; with the network plainly off, about 7. The timeout applies to every request the web makes, not only reviews.

A card deleted elsewhere shows a line saying so on the feedback screen, and 下一題 works as usual.

**For the developer to check in the browser:**

- Mid-session, set the network panel to Offline and answer: the verdict still appears at once; pressing Enter shows 儲存中…; after a few seconds an amber box says the answer is not saved, with 重試, and 下一題 is disabled.
- Still offline, press 重試: after a few seconds the box returns. The session has not moved.
- Go back online and press 重試: the box goes, 下一題 works, and the network panel shows exactly one successful `POST` for that answer. On the phone the card has moved once, not twice.
- Go offline for only a second or two around an answer: no box ever appears and the answer saves by itself.
- With a card on screen in the browser, delete that card on the phone, then answer it: a line says the card was deleted elsewhere, and 下一題 carries on to another card.
- Not practical to stage by hand: a lapsed Access session, and a 422. Both are covered by unit tests only.
