Status: ready-for-agent

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

- [ ] `GET /cards` returns every scheduling field, and a cached older response is still decodable
- [ ] A `review` answer moves the card and returns its new state
- [ ] A `training` answer records the row and leaves the card untouched
- [ ] `answeredAt` is stored verbatim, including a timestamp hours in the past
- [ ] A resubmitted `client_token` neither duplicates the row nor moves the card twice
- [ ] `countsTowardLadder` is gone from the model, the route and the tests
- [ ] Settings round-trip; an empty step list, a non-positive step and a non-positive new-card
      count are all rejected
