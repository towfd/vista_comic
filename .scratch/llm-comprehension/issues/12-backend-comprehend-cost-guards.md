# 12 — Backend `/comprehend` cost guards: daily cap + image-size ceiling

**What to build:** two independent anomaly guards on top of ticket 11's `/comprehend` endpoint. First, a lenient per-request image-size ceiling — both images are checked against it before any call to Claude, and an oversized request is rejected outright. Second, a global (not per-user — this backend has no per-user identity, per `docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md`) daily request-count cap, backed by a small Postgres counter table following `progress`/`saved_translation`'s existing `CREATE TABLE IF NOT EXISTS` precedent (no migration tooling), defaulting to 300/day. Both are pure anomaly guards (e.g. against a retry-loop bug), not real usage-limiting. Demoable by sending an oversized image and confirming rejection, and by exceeding the daily count and confirming rejection.

**Blocked by:** 11

**Status:** ready-for-agent

- [ ] `/comprehend` rejects a request whose crop or page image exceeds a defined size ceiling with a 4xx, before calling Claude
- [ ] A new Postgres table tracks a global daily request count (`CREATE TABLE IF NOT EXISTS`, no migration tooling)
- [ ] `/comprehend` increments the counter on each attempt and rejects with a 4xx once the daily cap (300) is exceeded, before calling Claude
- [ ] The daily counter resets naturally at the next calendar day (no manual reset step required)
- [ ] Backend tests cover both rejection paths (oversized image, cap exceeded) without needing to actually exhaust 300 real requests or send genuinely huge payloads in the test suite
