# 12 — Backend `/comprehend` cost guards: daily cap + image-size ceiling

**What to build:** two independent anomaly guards on top of ticket 11's `/comprehend` endpoint. First, a lenient per-request image-size ceiling — both images are checked against it before any call to Claude, and an oversized request is rejected outright. Second, a global (not per-user — this backend has no per-user identity, per `docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md`) daily request-count cap, backed by a small Postgres counter table following `progress`/`saved_translation`'s existing `CREATE TABLE IF NOT EXISTS` precedent (no migration tooling), defaulting to 300/day. Both are pure anomaly guards (e.g. against a retry-loop bug), not real usage-limiting. Demoable by sending an oversized image and confirming rejection, and by exceeding the daily count and confirming rejection.

**Blocked by:** 11

**Status:** resolved

- [x] `/comprehend` rejects a request whose crop or page image exceeds a defined size ceiling (8 MiB of base64 text per image) with a 413, before calling Claude
- [x] A new Postgres table (`ComprehendUsage`, `CREATE TABLE IF NOT EXISTS`) tracks a global daily request count
- [x] `/comprehend` increments the counter on each attempt and rejects with a 429 once the daily cap (300) is reached, before calling Claude — implemented as a single atomic `INSERT ... ON CONFLICT ... WHERE request_count < cap RETURNING`, so a rejected attempt does not keep bumping the stored count past the cap (a deliberate reading of "increments on each attempt": unbounded growth once already rejecting serves no purpose for a pure anomaly guard)
- [x] The daily counter resets naturally at the next calendar day (date-keyed row, UTC calendar day)
- [x] Backend tests cover both rejection paths via injected/monkeypatched low ceilings and a pre-seeded-at-cap table, not real oversized payloads or 300 real requests

## Comments

Implemented by `backend-implementer` on `feat/llm-comprehension-foundation`, in parallel with ticket 13. New: `backend/app/comprehend_usage_store.py`, `backend/tests/test_comprehend_cost_guards.py` (11 tests). Modified: `backend/app/db.py` (new `ComprehendUsage` table), `backend/app/main.py` (`_guard_image_size`/`_guard_daily_cap`, wired before the Claude call).

Fail-open vs. fail-closed: the daily-cap check fails **closed** (503) on a genuine store failure (`SQLAlchemyError`) — this guard exists for cost protection, so "can't verify the cap" must not silently become "allow anyway," unlike the read-side catalog/progress helpers that intentionally degrade for availability. It fails **open** only when the DB engine was never initialized at all (`RuntimeError`), which is unreachable in the real deployed app (the lifespan handler always calls `init_engine()` first) — that branch exists only so ticket 11's existing `test_comprehension.py` (which builds `TestClient(app)` without running the lifespan) doesn't start failing.

Verified independently: `pytest tests/test_comprehend_cost_guards.py tests/test_comprehension.py` — 25/25 pass.

Code review (`/code-review`, run jointly with ticket 13) found no hard violations; noted as judgment calls (not fixed, deemed acceptable): the "no per-user identity" rationale is repeated near-verbatim across three docstrings, and `get_count()` is currently only called by tests (a small, natural read-helper for the table this module owns, kept rather than inlined into the test file to preserve the existing pattern of tests only exercising a store module's public functions).
