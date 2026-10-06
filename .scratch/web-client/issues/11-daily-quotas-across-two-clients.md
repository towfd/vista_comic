Type: grilling
Status: open

# Daily quotas across two clients

## Question

Two of this system's limits are counted per day, and both were designed when there was exactly one client. What happens to them when a phone and a computer are both in use on the same day?

- **New cards per day** — `DEFAULT_NEW_CARDS_PER_DAY = 15` in `scheduler.py`, with `introducedOn` on the card. If fifteen new cards are met on the computer in the morning, does the phone offer any that evening?
- **The explanation cap** — `comprehend_usage_store` holds a daily cap on Claude requests, and `.scratch/comprehension-response-ux/` ticket 07 established that the cap is *reserved at enqueue* and refunded only when the request never reached Claude. Two clients enqueueing against one cap was not part of that design.

Both need the same thing checked first, and it is a fact rather than a decision: are these counted **server-side already**, or does either rely on the client tracking its own day? If the count lives in the backend, both may already behave correctly and this ticket closes as a verification. If either is client-side, it is a real decision, and it is the one place where honouring [iOS is not touched](02-backend-side-ocr-ios-untouched.md) may cost something.

It is on the map rather than inside a part's spec because it straddles two: the explanation cap belongs to ④ and the new-card quota to ⑥, and deciding it twice would be deciding it twice.

## Answer

_Unresolved._
