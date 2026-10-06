Type: grilling
Status: resolved

# Question generation on the web, scheduling from the backend

## Question

Feature parity includes review. Of the logic the review flow needs, what does the web implement itself and what does it take from the backend?

## Answer

**The web writes its own question generation and its own UI in TypeScript. Scheduling always comes from the backend.**

The inventory that produced this line: `Features/Study/` is 3,013 lines, cleanly split because seven of its files import no SwiftUI at all.

| Only on iOS (840 lines) | Already authoritative in the backend |
|---|---|
| `ClozeQuestion.swift` (185) — blanks and distractors | `scheduler.py` — the state machine |
| `SentenceAnswer.swift` (186) — sentence-rebuild grading | `ladder.py` — the 1/3/7/21/60/150/365 table |
| `PracticeQueue.swift` (206) — which cards, in what order | `card_review_store.py` — the review log |
| `PracticeRound.swift` (152) — assembling one round | `POST /cards/{id}/reviews` — returns the new schedule |
| `DeckWordMatching.swift` (111) — matching questions | `/cards`, `/study/settings` |

There is **no question-generation code in the backend at all** — no cloze, no distractors, no practice endpoint. `cloze` appears only as a recorded question type.

The developer chose two parallel implementations sharing only the database and the API, and reaffirmed it after being told the drift cost. That is the decision. Pushing question generation down into the backend was recommended and declined.

**Scheduling is the exception, and it is not a matter of taste.** A wrong question looks different; a wrong schedule means the two devices disagree about when a card is next due. `Scheduler.swift`'s own header explains why iOS carries a second copy — *"Offline practice cannot ask, so this exists"* — and states that the server's result wins, with `SchedulerParityTests` holding the two in step. **The web has no offline requirement, so that justification does not transfer.** It posts an answer and uses the schedule that comes back in the same response.

Four details the web would otherwise have to reproduce, and any one of which silently breaks agreement between devices:

1. A lapse costs **one slot, not everything** — via `previous_stage`, which is cleared once used.
2. **An answer given before a card is due moves nothing**, in either direction. The code names this as the only defence against a card being asked twice — which is exactly what two clients can cause.
3. A scheduling day starts at **04:00 Asia/Taipei**, not midnight.
4. Nothing reads a clock; `answered_at` is a parameter.

**What this means for iOS: nothing changes.** The web is a second caller of endpoints that already exist. Anything the web needs that the backend does not yet expose is an *added* endpoint, never a modified one.

The clients do share data, which is the point of parity — and point 2 above already absorbs the obvious hazard, where a phone holding a stale offline deck snapshot re-asks a card the computer has already answered. The answer is recorded; the schedule does not move.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map. The shared-quota half of the two-client question is not settled here — see [Daily quotas across two clients](11-daily-quotas-across-two-clients.md).
