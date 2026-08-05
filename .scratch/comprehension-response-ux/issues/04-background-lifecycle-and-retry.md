Type: grilling
Status: resolved

# Background lifecycle and manual retry

## Question

The explanation call now outlives the screen that started it. What happens to it when the app leaves the foreground, and how does a record that never got its explanation ever get one?

## Answer

**Keep running while foregrounded; abandon it otherwise; offer a manual retry on any record left without an explanation.**

iOS suspends in-flight work shortly after the app leaves the foreground unless it is explicitly handed to a background URLSession. That machinery was considered and rejected as disproportionate: the realistic case is a reader who taps Translate and keeps scrolling through the same chapter, which keeps the app foregrounded and the call alive. A reader who switches apps or locks the screen has stopped reading, and making them tap retry later is an acceptable cost for not introducing background-session plumbing.

**Retry sends the stored source text plus the page image re-fetched by `comic_id`/`chapter_id`/`page_number` — no images are ever stored.** The developer's own observation drove this: those three IDs are already persisted on the record (M8 added them for the jump-back-to-source-page feature), so the page image is always re-derivable from the catalog. The original selection crop is *not* re-derivable, because the crop rectangle isn't stored — and that is fine, because `/comprehend` treats `source_text` as ground truth and is explicitly instructed never to re-read text from the images (see `backend/app/comprehension_client.py`'s `_prompt_text`). The crop only ever contributed close-up visual context, and the full page still supplies scene context.

Persisting the crop image (or the crop rectangle) so retry could reproduce the original two-image call was considered and rejected: it would put an image blob on every record for a marginal context gain, when the developer's explicit preference is not to store images at all.

**A failed or abandoned call leaves the record intact with its translation.** It is never deleted, never hidden, and never silently retried — the reader sees a translation-only record with a retry affordance.

## Superseded in part by ticket 07

[Background comprehension task ownership and observation](07-background-task-ownership.md) moved the comprehension call out of the app and into a backend queue. That reverses this ticket's lifecycle answer. Read this ticket as amended below; the spec must state the amended version, not the original.

**Dead — do not carry into the spec:** "keep running while foregrounded, abandon it otherwise". The app no longer owns the call at all, so there is nothing to abandon. An enqueued job runs to completion whether the app is foregrounded, backgrounded, or killed, and survives a container restart (the lifespan worker reclaims `pending` rows). Backing the app out of the ownership question removed the trade-off this paragraph was reasoning about, rather than resolving it.

**Still true, and now load-bearing:** no images are ever stored, and the page image is re-derivable from the `comic_id`/`chapter_id`/`page_number` already on the record. Ticket 07 depends on this being true for the *first* call, not only for retry: the worker runs minutes after enqueue, with nothing in hand but the row. It re-reads the page from the same local library `/media/{comic_id}/{chapter_id}/{page}` serves (`backend/app/main.py:596`).

**Consequence — the crop image leaves the flow entirely.** This ticket left "make the crop optional, or send the page twice" as an open contract question for ticket 08. Ticket 07 collapses it: since *every* call is now deferred and the crop is not stored, no call ever has a crop. Every comprehension request is page-image-only. Ticket 08 confirms the resulting contract shape.

**Amended — what retry now means:** re-enqueueing the existing row rather than the app re-sending anything. The reader-visible behaviour is unchanged (a record left without an explanation offers a manual retry), and it still passes through the same daily-cap reservation, so no separate retry guard is needed. But because `pending` now genuinely means "still running", retry is no longer the routine stop-gap this ticket assumed — it is only for records that genuinely failed.

**Unchanged:** a failed record is never deleted, never hidden, never silently retried, and keeps its translation.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map. Partly superseded later the same day by ticket 07 — see the section above.
