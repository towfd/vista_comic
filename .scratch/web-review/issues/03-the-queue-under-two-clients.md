Type: grilling
Status: resolved
Blocked by: 01

# The queue under two clients

## Question

The phone builds its queue from a deck it holds: what is due, how many new cards the day has left, which learning card may be pulled forward. The web will port those rules — but a browser tab is a different kind of session. When does the web fetch the deck, and what does it do when the deck moves underneath an open session?

The cases to settle: the phone answers a card the tab still has queued; the tab stays open across the 04:00 rollover; a learning step comes due minutes later while the tab sits idle; the day's new-card allowance is spent on the other device.

## Answer

**The web holds a deck, keeps its own answers current from each review response, and fetches the whole deck again at three moments: on entering practice, when the tab comes back to the foreground, and before it says the day is done.**

What the server does and does not refuse decided how much the web has to carry (`backend/app/scheduler.py`, read 2026-10-12):

| Two devices both… | The server |
|---|---|
| answer a review card | **refuses the second**: an answer before `dueAt` is recorded and moves nothing |
| answer a learning card | **allows it, on purpose**: the duplicate costs one step and heals itself |
| introduce new cards | **knows nothing**: `newCardsPerDay` is only stored; each client counts `introducedOn` across the deck it holds |

So a stale deck can do exactly one kind of harm — introducing more new cards than the day allows — and everything else is either refused or harmless.

**Between fetches**, the response to each review carries that card's scheduling block (`state`, `learningStep`, `ladderStage`, `previousStage`, `introducedOn`, `dueAt`) and is written onto the card in the held deck. One request per question. Fetching the deck after every answer was offered and declined: it closes the gap below at the cost of doubling every wait and sending the whole deck once per question.

**The three fetches:**

- **Entering practice.** Deck and settings together.
- **The tab becoming visible again.** The ordinary way a deck goes stale is the reader going elsewhere and coming back.
- **Before the closing screen.** When the queue comes up empty, the deck is fetched once more and the queue asked again; only if it is still empty is the day called done. "Finished" is the one statement the session makes about the whole deck, so it is the one that must not be made from an old copy.

**A question on screen is never replaced.** If a fetch shows its card was answered on the phone in the meantime, the reader still finishes it and the new deck takes effect from the next question. The answer is posted as usual: the server absorbs it for a review card, steps a learning card once more, and returns 404 for a card that was deleted — handled as [An answer that cannot be posted](07-an-answer-that-cannot-be-posted.md) says. Swapping the question out was declined: it keeps the log cleaner by taking away something the reader is in the middle of typing.

**The accepted gap:** the tab stays visible the whole time while the phone introduces new cards. Nothing triggers a fetch, and the web can introduce up to its own stale allowance on top. It ends at the next of the three fetches.

**The clock is read every time the queue is asked, never held.** `now` and `today` are taken fresh for each question, so a tab left open overnight needs nothing special: the next question it computes sees the new day's allowance and whatever has come due. There are no timers — a tab sitting on the closing screen does not wake itself when a learning step comes due; it finds out when the reader returns to it, which is the second fetch.

**`today` is the browser's local calendar day, `yyyy-MM-dd`** — the string `PracticeView.today()` produces on the phone, and the one sent as `localDate`. Not the UTC day `toISOString()` gives, and **not** the 04:00 scheduling day either: 04:00 is where the server rounds day-length intervals, while the new-card allowance resets at local midnight on the phone, and the two clients share that allowance only by producing the same string.

## Comments

Per [What the engine must reproduce](01-what-the-engine-must-reproduce.md): the server's guard against an answer given early covers review cards only, not learning steps — so a learning card re-offered by a second client is not absorbed the way a review card is. The inventory also notes the day must be the reader's local day, not the UTC one.

Per [An answer that cannot be posted](07-an-answer-that-cannot-be-posted.md): the next question always waits for the review response, so within one tab the queue is never ahead of the server. What is left for this ticket is the other device, the clock, and whether a response patches one card or prompts a fresh `GET /cards`.

Resolved 2026-10-12 via `/grilling`. The clock and `today` paragraphs were filled in by the agent from the phone's code rather than put to the developer as choices. Settings are fetched with the deck; what a change made on the web's own settings page does to a session already running is the spec's to say.
