# 01 — The line-analysis resource

**What to build:** The backend side, end to end and testable without Claude: the line-analysis table and its migration, `POST /line-analyses` and `GET /line-analyses/{id}`, the worker that drains pending rows, and the Claude client that builds the structured-output request (prompt, schema, model mapping) and checks the result. See [the spec](../spec.md) — *The resource*, *The worker*, *The Claude call*.

**Blocked by:** None — can start immediately.

**Status:** done (2026-10-29) — on `feature/web-line-analysis`

**Notes from implementation**

- Server-side refusal fallback **is enabled**: the installed SDK (0.120.2) takes `fallbacks: "default"` on `client.beta.messages.stream` with the `server-side-fallback-2026-07-01` beta. Checked offline by capturing the serialized request through a mock transport. Only the text after the last `fallback` block is read as the answer.
- `refresh` on a `pending` analysis returns it unchanged (no reservation): it is already being made, and re-queueing it mid-run would race the worker.
- A restart marks interrupted rows `failed`/`interrupted` and refunds them rather than re-running them; rows still waiting their turn stay `pending` and run.
- Every failure refunds its reservation (the spec's rule), unlike `/comprehensions`, which keeps a reservation that reached Claude.
- `max_tokens` starts at 8000 and effort is left at each model's default; ticket 02 tunes both.

**Acceptance criteria**

- [x] A migration creates the table; the migration test passes
- [x] POST returns a stored `done`/`pending` analysis for the same (source key, translation, model) with no reservation; `refresh` re-queues it with one
- [x] A new analysis is created `pending` with one reservation; a `failed` one is re-queued with one; an exhausted cap is a 429 and changes nothing
- [x] GET returns one analysis, 404 when missing
- [x] The worker turns a pending row into `done` with the parsed result, or `failed` with `error` / `refused` / `invalid`, refunding the reservation on failure; orphaned claims are released at startup as `interrupted`
- [x] The request uses the mapped model ID, `output_config.format` with the agreed schema, the agreed prompt, the names, line and translation, no image, and streaming; whether server-side refusal fallback is enabled is recorded here
- [x] A result with no words, or a word not found in the line, is `invalid`
- [x] All of it covered by pytest with a stubbed client; the existing backend suite still passes
