# 15 — The comprehension record resource: table, six endpoints, quota reservation

**What to build:** The backend can accept, store, list and manage comprehension records over HTTP. Nothing runs the Claude call yet — an enqueued record simply stays `pending`, which is exactly what the next ticket picks up. Verifiable entirely with curl.

The old saved-translation table is replaced by a comprehension record table whose rows double as the work queue. `status` is a single column with five values — `pending`, `running`, `ok`, `declined`, `failed` — and is the only discriminator; the old "all three note columns are NULL means translation-only" convention is gone because it cannot tell pending from failed.

The row holds: source text, the on-device translation (written at enqueue, never modified afterwards), a nullable cloud translation, the three nullable note fields, target language, comic/chapter/page, status, a read flag, the model tier to use, the UTC date its quota reservation drew from, and a creation timestamp. **No images, ever.**

Six endpoints replace the translations endpoints: enqueue, list, fetch one, mark read, retry (failed only), delete. List and fetch-one also return the comic and chapter **titles**, joined at read time from the catalog already held in memory and null when the comic has left the library — the stored ids are truncated hashes, fine as keys and unusable as labels.

The daily cap guard moves off the old comprehend endpoint onto enqueue: an exhausted cap returns 429 immediately and **creates no record**, so the queue can never exceed the remaining budget. The reservation's UTC date is stored on the row so a refund goes back to the day it was drawn from.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The saved-translation table is replaced by the comprehension record table with the columns above; the deployment step that drops the old table is documented in the repo.
- [ ] Enqueue returns a `pending` record immediately, echoing its server-generated id and timestamp.
- [ ] Enqueue reserves one unit of the daily cap and records the UTC date of that reservation on the row; when the cap is spent it returns 429 and no row is created.
- [ ] Deleting a `pending` record refunds its reservation against that row's stored date, not today's.
- [ ] List returns records newest-first; list and fetch-one both carry comic and chapter titles, null for a comic no longer in the catalog.
- [ ] Mark-read sets the read flag; retry is accepted only for a `failed` record, returns it to `pending`, and takes a fresh reservation.
- [ ] Retry on a record in any other status is rejected rather than silently accepted.
- [ ] A store-level failure surfaces as an error rather than degrading into an empty list, matching the existing convention for this kind of store.
- [ ] Endpoint tests cover all six through the existing test-client harness; store tests run against the throwaway database using the existing engine fixture.
