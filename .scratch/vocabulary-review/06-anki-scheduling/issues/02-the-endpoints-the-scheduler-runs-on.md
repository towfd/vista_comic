Status: implemented on branch `feat/anki-endpoints`, 2026-08-31

# 02 — The endpoints the scheduler runs on

**What to build:** The API surface the app needs to run a session: cards that carry their
scheduling state, an answer that returns the card's new state, and settings.

`GET /cards` carries `state`, `learningStep`, `dueAt`, `ladderStage` and `previousStage`. The app
caches this response wholesale as its deck snapshot, so the fields have to be here rather than on
a separate call — the same reasoning that put `ladderStage` in the first release before anything
read it.

`POST /cards/{id}/reviews` takes `context` (`review` / `training`) and `answeredAt`, and returns
the card's new state — which the app writes straight into its snapshot rather than refetching.
**`countsTowardLadder` is removed**: it existed so a topped-up card would not move the rung, and
there is no top-up any more. A `training` answer records the row and schedules nothing.

`answeredAt` is stored as given. `reviewed_at` stays as the receipt time; they differ by hours
after an offline flush, and that difference is the point.

`GET`/`PUT /study/settings` reads and writes the single settings row: `learningSteps` (minutes,
ordered, non-empty) and `newCardsPerDay`. Validate both — an empty step list or a zero-minute
step would schedule a card to be due before it was answered.

**Blocked by:** 01.

- [x] `GET /cards` returns every scheduling field
- [x] A `review` answer moves the card and returns its new state
- [x] A `training` answer records the row and leaves the card untouched
- [x] `answeredAt` is stored verbatim, including a timestamp hours in the past
- [x] A resubmitted `client_token` neither duplicates the row nor moves the card twice
- [x] `countsTowardLadder` is gone from the model, the route and the tests
- [x] Settings round-trip; an empty step list, a non-positive step and a non-positive new-card
      count are all rejected

## What was built

`GET`/`PUT /study/settings`, the scheduling block on `LearningCardResponse`, and
a `ReviewOutcome` that carries the card's whole new state so the app can write it
into its snapshot rather than refetch.

**Three renames, and none of them is cosmetic.** `step` became `state` (it stopped
being a position in a day the moment the day stopped resetting), `dueOn` became
`dueAt` (a date cannot say 20:07), and `ladderMoved` became `intervalChanged`,
which is a different question rather than the same one reworded — see ticket 01.

**`countsTowardLadder` is gone, replaced by `context`.** The flag could say only
*whether* an answer counted, never why; `context` says which mode asked, which is
what the log actually needed. The current app still sends the flag and Pydantic
ignores unknown fields, so nothing breaks before ticket 04 removes it there.

**`answeredAt` is optional, and that is deliberate.** The app cannot send it until
ticket 07, and the server falls back to its own clock — which for every answer
this build can send is true rather than merely convenient, because an online
answer arrives when it happens.

**One checkbox moved to ticket 03**: "a cached older response is still decodable"
is about the app's deck snapshot, not this API. The snapshot decoder needs a
lenient path for a cached payload that has `dueOn` and no `dueAt`, and that code
does not exist on this side.
