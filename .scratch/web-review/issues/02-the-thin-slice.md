Type: grilling
Status: resolved
Blocked by: 01, 04

# The thin slice

## Question

What is in the first spec, and what is deliberately left for after it?

~~Which of the four question types~~ — settled, see Comments: cloze typed and translate, both in the first slice. What remains is which of the three in-scope extras (settings page, fixing a card mid-practice, entering from the reader) go in with them.

And whether the first slice posts real reviews at all. Reading progress was cut from the reader MVP because a wrong write from the web corrupts the phone's data; the same is true of a review.

## Comments

Both blockers resolved 2026-10-12. Typed questions are workable ([Typing Vietnamese at a desk](04-typing-vietnamese-at-a-desk.md)); the price of each mode, and the fact that translate is the only one able to ask every card, are in [What the engine must reproduce](01-what-the-engine-must-reproduce.md).

**Question types settled 2026-10-12, by the developer directly rather than through this ticket:** the web asks cloze typed and translate, and the other two are out of scope for the map, not merely out of the slice. No card is stranded by this — translate can ask every card, word cards included, so a card that supports no cloze is asked by translation. By the inventory's count the engine is then roughly 90 lines for typed cloze with its deck-word matching, 13 for translate and 55 for the queue. Still open here: the extras, and whether the first slice posts real reviews.

## Answer

**The first spec is: the deck, two question types, the queue, real reviews, the settings page, and fixing a card in the middle of practice. Entering from the reader comes after it, and is the only thing that does.**

In the slice:

- **Cloze typed and translate** — the only two types the web asks at all.
- **The queue**, ported: what is due, the day's allowance of new cards, the learning card pulled forward.
- **Real reviews.** Every answer is posted with `context: "review"` and moves the card. A slice that posted nothing was considered and declined: the web's queue moves only by the schedule the server returns, so a card answered without a write never leaves the queue and the session cannot end — which is endless training, already ruled out. The risk is the same one reading progress carried, a wrong write that the phone then sees; it is held by the judging tests and by the token that stops a resubmission counting twice.
- **The settings page** — reading *and* writing `learningSteps` and `newCardsPerDay`, rather than reading only and sending the reader to the phone to change them.
- **Fixing a card mid-practice** — correcting or deleting a card from the question that exposed it.

After the slice: **entering practice from the reader.** The first version has one fixed entrance.

The recommendation was to take none of the three extras into the first spec, since everything in it is already new to the web. The developer took two. The slice is therefore not as thin as the reader MVP was, and the spec should expect to be cut into more tickets than that one's three.

## Comments

Resolved 2026-10-12 via `/grilling`. Fixing a card graduates into its own ticket, [Fixing a card mid-practice](09-fixing-a-card-mid-practice.md). The settings page does not: nothing about it is undecided beyond what the spec's own grilling will ask.
