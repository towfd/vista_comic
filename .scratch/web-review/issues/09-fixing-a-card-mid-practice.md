Type: grilling
Status: resolved
Blocked by: 03

# Fixing a card mid-practice

## Question

The reader is answering, sees that a card is wrong, and fixes it there. What can be fixed, at which moment, and what becomes of the question on screen?

What can be changed — the translation only, or the source text too, which is the answer being asked for — and whether deleting and resetting are offered beside editing. Whether the fix is available before answering, which shows the answer, or only once the verdict is in. And what happens to the answer just given: a card marked wrong because its own text was wrong has had a lapse recorded against it by the time the reader can say so.

It borrows `PATCH` and `DELETE /cards/{id}` from part ⑤ of the web client without building the card library. It waits on [The queue under two clients](03-the-queue-under-two-clients.md) because a card edited or deleted under a running session is the same event as the phone doing it.

## Answer

**After the verdict, and only then, the reader can change the card's translation, change its kind, reset it, or delete it. The source text cannot be changed, and the answer just given stands.**

**The source text is out of reach.** `PATCH /cards/{id}` accepts `translation` and `kind` and deliberately refuses everything else — the source is half the card's identity and is tied to the page it was read from (`models.LearningCardUpdate`). Making it editable would change an existing endpoint, which the web client's map forbids. So a card whose *source* is wrong — a misread bubble — has one remedy on the web: delete it, and collect it again on the phone.

**All four actions the backend offers are in**, against a recommendation of the first and third only:

| Action | Endpoint | What happens to the session |
|---|---|---|
| Change the translation | `PATCH /cards/{id}` | the card stays where its schedule put it, with the new wording next time |
| Change the kind (word / sentence) | `PATCH /cards/{id}` | later questions are built from the deck as it now is, which can change what may be blanked |
| Reset | `POST /cards/{id}/reset` | the card is `new` again and comes back as one, under the day's allowance like any other |
| Delete | `DELETE /cards/{id}` | the card leaves the deck; a real delete, asked for twice |

Each returns the card (or nothing, for delete), and the held deck is updated from that, the same way a review response updates it. None of them needs a fetch of the whole deck.

**Only on the feedback screen.** The question screen stays a field and nothing else. This is also when a wrong card is usually noticed — with the source text finally in view. The cost is that a card recognisably broken at first sight still has to be answered, or answered blank, before it can be dealt with. Offering the actions before answering was declined.

**They wait for the review to be saved.** The answer is posted at Enter and [the next question waits for its response](07-an-answer-that-cannot-be-posted.md); the fixing actions wait on the same thing, so a reset can never race the review it is meant to wipe out.

**The answer just given is not taken back.** By the time the reader can say the card was wrong, the lapse it caused is recorded, and the backend has no way to void a review. That is accepted: a lapse costs one slot rather than everything, the next correct answer earns it back, and reset is there for a card whose history is not worth keeping. Two ways round it were declined — an added endpoint that voids the last review, which reaches into the scheduler and the review log and which the phone's offline copy of the scheduler would know nothing about; and holding the post back until the reader moves on, which would undo the reason the wait is invisible.

## Comments

Resolved 2026-10-12 via `/grilling`. The "what happens to the session" column and the wait-for-the-review rule were filled in by the agent as consequences rather than put to the developer as choices. How the actions are laid out — inline, a menu, a dialog — and their keyboard access are the spec's.
