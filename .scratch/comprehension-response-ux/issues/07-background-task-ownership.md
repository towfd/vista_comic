Type: grilling
Status: resolved

# Background comprehension task ownership and observation

## Question

The explanation call must outlive the sheet that started it, and two different screens need to see its progress: the result screen (which fills in live if the reader is still watching, per ticket 05) and the History tab (which badges when it lands). Today that work is a plain `Task` inside `CroppedSelectionPreview`, which dies with the view.

Where does the in-flight work live instead — an app-level `@Observable` store injected through the environment, something owned by `RootTabView`, or another shape? How do both screens observe it without either of them owning it? How do concurrent calls behave when the reader translates several selections in a row? And where does "cancel when the app leaves the foreground" (ticket 04) actually hook in?

Consider what the codebase already establishes: `LoadState` is the convention for a fetch that replaces what's displayed, while `isUpgrading`/`upgradeError` and `VocabularyView.deleteError` are the precedent for in-place work that must not disturb surrounding content. Neither precedent covers work that outlives its view, so this may need a genuinely new shape — justify it against the project's "minimum architecture for current acceptance criteria" rule.

## Answer

**The in-flight work does not live in the app at all — it moves to the backend. This reverses [ticket 04](04-background-lifecycle-and-retry.md)'s client-owned lifecycle.**

The app's responsibility ends when it enqueues. There is no app-level store, no `RootTabView`-owned state, and no new architectural layer: the question "what new shape holds work that outlives its view" is answered by removing the work from the view tree entirely. The client keeps only the existing `LoadState` + `.task` convention.

The decisive fact came from the backend, not the app: the backend already holds every page image on local disk and serves it from `/media/{comic_id}/{chapter_id}/{page}` (`backend/app/main.py:596`). Combined with ticket 04's "no images are ever stored, the page is re-derivable from `comic_id`/`chapter_id`/`page_number`", the backend can reconstruct everything a deferred call needs without the client holding anything.

### Backend execution: a DB-backed queue drained by a lifespan worker

The record row *is* the queue. A polling loop started in the existing `lifespan` handler (`backend/app/main.py:95`) claims `pending` rows and runs them. No new compose service — the deployment stays `api` / `postgres` / `cloudflared`, and `backend/Dockerfile:29` runs a single uvicorn worker, so no leader election is needed.

**The worker runs as a plain daemon `threading.Thread`, not an `asyncio` task** (sharpened after this ticket was first resolved; see the correction note below). This backend is entirely synchronous — SQLAlchemy sync sessions over psycopg — so an asyncio worker would have to wrap every DB read and write in `asyncio.to_thread`, introducing the codebase's first sync/async seam purely as an artifact of how the loop was started. A thread keeps the worker as the plainest possible `claim -> run -> write back` loop and leaves the sync/async question entirely absent rather than displaced.

FastAPI `BackgroundTasks` was considered first and rejected on one limitation: it lives in the api process, so a container restart mid-call vaporizes the task with no trace, leaving a row stuck in `pending` that is **indistinguishable in the data from a call still running**. That would have forced a "waited too long" threshold onto the result screen and the History tab — pushing an implementation artifact into ticket 09's UI. The worker's restart recovery buys that back: `pending` genuinely means "still running". Redis + arq/Celery was rejected as over-engineering for a single-user, single-device app.

**Concurrency: at most 3 jobs at once, FIFO by creation time.** Unbounded was rejected because a runaway retry loop could burn the whole daily quota in minutes, and because nothing else in the design bounds spend once work is enqueued. Strictly serial was rejected as an unnecessarily slow experience when three selections are made on one page. **3 is a tunable constant, not a load-bearing design premise; the spec should present it as such.**

> **Correction.** When first resolved, this cap was justified primarily by threadpool contention — every route being a sync `def` sharing Starlette's ~40-thread pool, so unbounded LLM calls would supposedly stall `/media` page serving. That argument does not survive scrutiny at this scale: one user, at most a handful of concurrent page-image requests, and 40 threads. **The real and sufficient reason to cap concurrency is Claude spend.** The conclusion is unchanged; the reasoning behind it is. See the map's Out of scope for why the backend is staying synchronous.

**Per-attempt Claude timeout: 120 seconds.** `backend/app/comprehension_client.py:99` currently constructs `anthropic.Anthropic()` with no `timeout` and no `max_retries`, taking the SDK defaults of 600s and 2 automatic retries — one hung call could hold a concurrency slot for over ten minutes. A real call is ~10–30s, so 120s already means something has gone wrong. Note that 120s is the ceiling *per attempt*: with the SDK's 2 retries left in place, a worst-case job still occupies its slot for roughly 6 minutes.

### Observation: polling, with the backend as the single source of truth

No shared client store. The unread flag is a backend column, and each screen fetches for itself:

- The result screen polls its own record while that record is `pending`.
- The app refetches the list when it returns to the foreground (`scenePhase` — **new to this codebase; nothing uses it today**).
- The History tab refetches on appear.

Marking-read is a write to the backend, so the badge simply stops counting that record on its next refresh — no cross-screen wiring, no second source of truth to reconcile. SSE/long-poll was rejected (every route here is sync `def`, and it would mean holding a connection through the Cloudflare tunnel); APNs was rejected as disproportionate (push certificates, a device-token table, and it can't be verified in the simulator).

The accepted cost: the badge only moves while the app is open. An explanation that completes while the app is closed is discovered on next launch.

### "Cancel when the app leaves the foreground" hooks in nowhere — it is gone

Nothing cancels, and a job that has been enqueued always runs to completion. What that removed was cost protection, so the daily cap takes over the job:

**Reserve on enqueue, settle only when the request never reached Claude.** `_guard_daily_cap` (`backend/app/main.py:472`) moves from `/comprehend`'s request path to the new enqueue endpoint, so a cap-exhausted state still returns 429 *immediately*, no record is created, and the reader still has the on-device translation from ticket 02. The queue therefore can never be longer than the remaining quota.

The reservation's `usage_date` is stored **on the job row**. `comprehend_usage_store` keys its counter by UTC date (`backend/app/comprehend_usage_store.py:34`), so a job reserved at 23:59 and run at 00:00 must refund against the day it was reserved on, not "today" — otherwise a crossed-midnight refund silently hands today an extra request.

Only "the request never reached Claude" refunds: deleted while `pending`, or the worker failing before it issues the call. Anything that reached Claude keeps its count — including `declined`, which produced billable tokens. Full settlement (refunding Claude-side 5xx/timeouts too) was rejected: the SDK's own retries mean a "failure" may already have partially billed, and refunding failures is exactly what would let a retry-loop bug run free, which is the guard's whole purpose.

## Comments

Resolved via a `/grilling` session on 2026-08-05.

Consequences pushed onto other tickets (all recorded on those tickets):

- **[04](04-background-lifecycle-and-retry.md)** — its foreground/abandon lifecycle is superseded; its no-stored-images constraint survives and becomes load-bearing.
- **[08](08-history-record-data-model.md)** — the record row is now also the queue row, the unread flag is a backend column, and the crop image drops out of the contract entirely.
- **[09](09-reader-result-screen-states.md)** — no "waited too long" state is needed; the screen polls instead.
- **[05](05-unread-badge-semantics.md)** — semantics unchanged, implementation pinned to a backend column plus per-screen fetches.
