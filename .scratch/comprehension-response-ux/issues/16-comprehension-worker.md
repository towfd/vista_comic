# 16 — The worker: enqueued records become explanations on their own

**What to build:** A record enqueued in the previous ticket now gets picked up and completed without anyone asking. Post a record with curl, wait, fetch it again: it holds a cloud translation and three explanation notes. Close the laptop lid, restart the container mid-flight, and it still completes.

A polling loop started in the existing lifespan handler claims `pending` rows and runs them, **as a plain daemon thread rather than an asyncio task** — this backend is entirely synchronous, and an asyncio worker would have to hop every database call into a thread anyway, introducing the codebase's first sync/async seam purely as an artifact of how the loop was started.

The worker has everything it needs on the row: it re-reads the page image from the library on disk, downscales it to a 1024px long edge (a **new Pillow dependency** — the backend has no image library today, and sending raw scans would cost several times more per call), and calls Claude with the page image only. The selection crop is gone from the flow entirely: it was never stored and a deferred call cannot reproduce it.

**Recovery on restart is a blanket update of `running` back to `pending` at startup.** This is correct rather than merely convenient — the container runs a single uvicorn worker, so if the process has just started, nothing can still be executing. That is what makes `pending` genuinely mean "still running", which later UI tickets rely on to avoid inventing a "this probably died" state.

**Blocked by:** 14 (both change how the tool schema is built), 15 (the table and store it drains).

**Status:** ready-for-agent

- [ ] A drainable step — claim up to N pending rows, run them, write terminal state back — is callable synchronously, so its tests need no threads and no sleeps. The daemon thread is a loop around it holding no logic of its own.
- [ ] Claiming is atomic: two concurrent claims never take the same row.
- [ ] At most 3 jobs run concurrently, oldest first. The cap is a named, documented constant whose comment says it bounds Claude spend — **not** thread pressure, which does not bite at this scale.
- [ ] The Claude client is constructed with a 120-second per-attempt timeout, documented as such, instead of the SDK's ten-minute default.
- [ ] The worker reads the page from the library by the row's comic/chapter/page, downscales to a 1024px long edge, and sends only that image.
- [ ] A successful call writes the cloud translation and the three notes and sets `ok`; a declined result sets `declined`; any other failure sets `failed`. The on-device translation on the row is never modified.
- [ ] The quota reservation is refunded **only** when the request never reached Claude — deleted while pending, or a failure before the call was issued. A declined result keeps its count, because it produced billable tokens.
- [ ] On startup, every `running` row returns to `pending`, and a restart mid-flight results in the record completing rather than stranding.
- [ ] Worker tests stub Claude through the existing client-construction seam; image downscaling has a direct unit test.
