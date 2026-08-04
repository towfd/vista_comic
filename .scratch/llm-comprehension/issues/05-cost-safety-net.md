Type: grilling
Status: resolved

# Cost safety net

## Question

Given the comprehension call now costs real money per request (unlike the free on-device frameworks it partly replaces), does this need a cost-safety mechanism, and if so, per-user or global?

## Answer

**A simple global daily request cap**, enforced backend-side — not a per-user quota system. The backend has no user-identity system to key a per-user limit on: Cloudflare Access (`docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md`) authenticates via a single shared Service Token identifying the app as a whole, not individual users, consistent with this being a single-developer, single-user backend throughout M1–M8. A generous global daily cap, set well above normal personal usage, is purely an anomaly guard against bugs (e.g. a retry loop) generating runaway Claude API spend — not real usage-limiting.

The exact cap value and enforcement mechanism (env var, in-memory counter, DB-backed counter table) are deferred (see ticket 10).

## Comments

Resolved via a `/grilling` session on 2026-08-01, in the same conversation that created this map.
