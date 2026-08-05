Type: grilling
Status: resolved

# History record data model and API shape

## Question

A history record now has a lifecycle the old saved-translation row never had: created with a translation only, later completed with an explanation, possibly failed and awaiting retry, and separately read or unread. What shape holds that?

Specifically:

- Does this reuse `saved_translation` (adding status/read columns) or replace it with a new table? Existing rows are disposable (ticket 03), so migration is not a constraint — only clarity is.
- What distinguishes "explanation still coming," "explanation arrived," "explanation failed, retry available," and "explanation declined by content policy"? M9 relied on all three note columns being `NULL` to mean "translation only", which can no longer distinguish pending from failed.
- Does the read/unread flag live on the server or on-device? It is a UI concern on a single-user, single-device app — weigh a server column against `UserDefaults`-style local state.
- What replaces `POST /translations`'s save role, and what does the History tab's list endpoint need to return?
- ~~`/comprehend` currently requires *both* a crop image and a page image, but retry only has the page image (ticket 04). Does the crop become optional, does retry send the page image twice, or does the contract change shape?~~ — **settled by ticket 07**, see below.

## Constraints from ticket 07

[Background comprehension task ownership and observation](07-background-task-ownership.md) moved the comprehension call into a backend queue. Three of the bullets above are now partly or wholly decided, and one new requirement lands on this ticket:

- **The record row is also the queue row.** A lifespan worker claims `pending` rows, at most 3 concurrently, FIFO by creation time. Whatever shape this ticket picks must support atomic claiming and restart recovery (a row claimed by a process that died must become claimable again). This is the strongest argument yet for a new table over extending `saved_translation`.
- **The read/unread flag is a server column.** Decided: ticket 07 chose "backend is the single source of truth, each screen fetches for itself", which rules out `UserDefaults`. The open part is only what to name it and whether the list endpoint returns a count.
- **A `usage_date` (or equivalent) must live on the row.** The daily cap is reserved at enqueue and refunded — against the reservation's own UTC date, not "today" — only when the request never reached Claude. `comprehend_usage_store` keys by UTC date, so the row has to remember which day it drew from.
- **No images anywhere in the contract.** Every call is deferred and no image is stored, so the worker only ever has the row plus the page image it re-reads from disk. Every comprehension request is page-image-only; the crop is gone. Confirm the resulting `/comprehend`-successor contract.
- **The client no longer calls `/comprehend` directly.** What replaces `POST /translations` is now an *enqueue* endpoint that returns a pending record immediately; the list endpoint feeds both the History tab and the badge; a per-record fetch feeds the result screen's poll. The existing synchronous `/comprehend` becomes internal to the worker, or goes away — decide which.

## Answer

### The table: `saved_translation` is dropped and rebuilt as `comprehension_record`

The deciding fact is that this backend has **no Alembic** — `db.init_engine` calls `Base.metadata.create_all` (`backend/app/db.py:126`), which is `CREATE TABLE IF NOT EXISTS` and will happily create a new table but will **never add a column to an existing one**. So every path here needs a manual `DROP TABLE saved_translation` (the map's Notes already establish the rows are disposable). Given the drop is unavoidable, renaming costs nothing extra in deployment work — `create_all` builds the new table automatically — and it buys an honest name: these rows are no longer a reader's deliberate saves, they are automatic records that double as a work queue.

**The `DROP TABLE saved_translation` must be written into the spec as an explicit deployment step, noted as the last manual drop** — adopting Alembic is triggered by this schema landing (see the map's Out of scope). If it is forgotten, `create_all` silently does nothing and the app fails at runtime with "column does not exist", which reads like a code bug rather than a missed deploy step. A startup schema check was considered and rejected as machinery for a one-time action.

| Column | Notes |
| --- | --- |
| `id` | surrogate PK, as before |
| `original_text` | the source text, possibly OCR-corrected by the reader |
| `translated_text` | the **on-device** translation (ticket 02), written at enqueue, never modified afterwards |
| `cloud_translation` | Claude's own translation; filled only on `ok`, nullable |
| `grammar_notes` / `context_notes` / `tone_register` | filled only on `ok`, nullable |
| `target_language` | as before |
| `comic_id` / `chapter_id` / `page_number` | as before; now also how the worker re-reads the page image from disk |
| `status` | `pending` / `running` / `ok` / `declined` / `failed` |
| `is_read` | boolean; the unread badge's server-side truth (ticket 07) |
| `use_stronger_model` | boolean; which Claude tier the worker must call — **added by ticket 09** |
| `usage_date` | the UTC day this record's quota reservation drew from |
| `created_at` | replaces `saved_at` — nothing is "saved" any more |

**M9's "all three note columns NULL means translation-only" trick is dead.** It could not distinguish pending from failed, which is the whole point of this ticket. `status` is now the only discriminator, and the note columns carry no state meaning at all.

### `status` is one column with five values

A single column serves both readers of this row. The worker claims atomically with `UPDATE ... WHERE status = 'pending' ... RETURNING`; the UI renders `status` directly. Splitting it into a separate outcome column plus a queue-state column was rejected — two columns admit illegal combinations (`running` with an outcome already set) that then need an invariant nobody enforces.

Keeping `running` as a distinct value rather than hiding claiming behind a `claimed_at` timestamp has a second payoff: it turns ticket 09's "should queued look different from being-explained?" into a free UI choice instead of something the data layer has already foreclosed.

**Recovery on restart is a blanket `UPDATE ... SET status = 'pending' WHERE status = 'running'` at startup.** This is exactly correct rather than merely convenient, because `backend/Dockerfile:29` runs a single uvicorn worker: if the process has just started, nothing can still be executing, so every `running` row is by definition orphaned. No heartbeat, no lease expiry, no `claimed_at`.

**A failed record stores no reason.** `declined` is already its own status, so `failed` means network/backend/Claude error, and the reader's available action is identical regardless of which. Details go to the existing `logger.warning` convention.

### Display precedence: cloud translation wins, device translation is the fallback

Both translations are kept on the row. The UI shows `cloud_translation` when it is present and falls back to `translated_text` otherwise — so `pending`, `failed`, and `declined` records naturally show the device translation with no extra flag. Keeping both is cheap insurance specifically because schema changes here are expensive (no Alembic means another manual drop), and it leaves ticket 09 free to decide *how* the swap is presented without the data model having pre-empted it.

### Endpoints

```
POST   /comprehensions              enqueue -> 201 pending record; 429 when the cap is spent, and no row is created
GET    /comprehensions              list, newest created_at first
GET    /comprehensions/{id}         one record — the result screen's poll
PATCH  /comprehensions/{id}         { "isRead": true }
POST   /comprehensions/{id}/retry   failed only; resets to pending and re-reserves quota
DELETE /comprehensions/{id}         refunds the reservation if the row was still pending
```

`POST /comprehensions` takes `originalText`, `translatedText`, `targetLanguage`, `comicId`, `chapterId`, `pageNumber`, `useStrongerModel` — no images (see below). **`useStrongerModel` was added by [ticket 09](09-reader-result-screen-states.md)** and is a genuine gap this ticket missed: M9 passed the tier as a per-call argument to a synchronous endpoint, but the worker now runs minutes after enqueue, so the tier has to be persisted on the row rather than held in the request. Responses stay camelCase per `backend/app/models.py`'s existing iOS-mirroring convention; `usage_date` is internal and not exposed.

**Added by [ticket 10](10-history-tab-ui.md): the list and single-record responses also carry `comicTitle` and `chapterTitle`, joined at read time from the in-memory catalog** (`main.py:118` `_require_catalog`), both nullable for a comic that has since left the library. This ticket treated `comic_id`/`chapter_id` as sufficient source identification, but they are 16-hex-char SHA-1 prefixes (`ids.py:20`) — fine as opaque keys, unusable as the label on a browsable list. They are joined rather than stored so a rename stays correct and nothing is duplicated.

Retry gets its own path rather than a `PATCH {"status": "pending"}`: re-enqueueing is a domain action with its own precondition and its own quota reservation, and handing the client arbitrary status transitions would leak the state machine into the API.

**`POST /comprehend` is removed.** `_guard_image_size` goes with it (no client ever uploads an image again) and `_guard_daily_cap` moves to `POST /comprehensions`. `comprehension_client.py` stays as the Claude seam the worker calls directly. `test_comprehension.py`'s endpoint tests get rewritten as worker tests — they currently test behaviour that will no longer exist.

### Images: the backend downscales, and this needs a new dependency

Ticket 07 put the Claude call minutes after enqueue, and ticket 04 forbids storing images, so the worker's only source for the page image is the library on disk — at full scan resolution. **Today the downscale to a ~1024px long edge happens on iOS** (`APIComprehender.swift:38`, `:163`), and the backend has **no image library at all** — `backend/requirements.txt` has no Pillow. Sending a raw scan would cost roughly 2–5x more per call (Claude bills images at about `width * height / 750` tokens) and risks its size limits.

**Add Pillow; the worker downscales to a 1024px long edge before encoding**, reproducing the current iOS behaviour server-side. Uploading a pre-downscaled image at enqueue was rejected: it both contradicts ticket 04 and puts an image upload on the one request whose whole purpose is to return instantly. Dropping the page image entirely was considered — it would erase this problem completely — but rejected as a real quality regression against M9's premise that Claude sees the scene; ticket 11's prototype is the right place to test whether the page image earns its keep.

### Worker loop, assembled

1. On startup: `running` -> `pending`.
2. Claim up to 3 `pending` rows, oldest `created_at` first, atomically.
3. Read the page from disk, downscale to 1024px long edge, JPEG-encode, call `comprehension_client` with a 120s per-attempt timeout (ticket 07).
4. Write a terminal `status`; on `ok` also write `cloud_translation` and the three notes. Refund the reservation against the row's own `usage_date` only when the request never reached Claude.

### Judgment calls made without a separate question

- The unread count is computed client-side from the list; no count field and no count endpoint. The badge already fetches the list.
- No pagination on `GET /comprehensions` yet — see the map's Not-yet-specified.
- `is_read`, not `read`.
- No `attempt_count` column.
- Deleting a `pending` row refunds its reservation, following directly from ticket 07's refund rule.
- `docs/api-contract.md` currently documents none of the translation/comprehension endpoints, so whether to extend it is left to the spec.

## Comments

Resolved via a `/grilling` session on 2026-08-05.

Consequences pushed onto other tickets:

- **[09](09-reader-result-screen-states.md)** — five status values to render, two translations with a fixed precedence, and a new 429 case at enqueue.
- **[10](10-history-tab-ui.md)** — unblocked; also absorbs the map's empty/unreachable-backend fog patch.
- **[12](12-client-removal-boundary.md)** — newly created; this ticket deleting `POST /comprehend` and `POST /translations` is what made the client-side removal boundary specifiable.
