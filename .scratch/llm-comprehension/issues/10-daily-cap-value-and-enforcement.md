Type: grilling
Status: resolved

# Daily cap value and enforcement

## Question

What's the actual daily request cap value (ticket 05), and where/how is it enforced — an in-memory counter, a small DB-backed counter table (mirroring `progress`/`saved_translation`'s existing precedent), or an env-configured limit?

Resolve via `/grilling`.

## Answer

**Mechanism: a small Postgres table**, mirroring `progress`/`saved_translation`'s existing precedent (`CREATE TABLE IF NOT EXISTS`, no migration tooling) — e.g. `(date, count)`, checked/incremented before each comprehension call. Redis was considered (it's a genuinely more idiomatic fit for expiring counters via `INCR`/`EXPIRE`) but rejected for now: M5 already decided "Redis was not needed" (`docs/adr/0004-docker-compose-topology.md`), and introducing a whole new Compose service/dependency for a single anomaly-guard counter is disproportionate. The stated reason to reconsider Redis — an upcoming caching need when fetching manga — is not yet a decided, scoped requirement, so it doesn't justify adding the infrastructure now. Revisit Redis once caching is actually planned; the two needs can share one Redis instance at that point.

**Value: 300 requests/day**, global (not per-user — no per-user system exists, per ticket 05). This is purely an anomaly guard (e.g. against a retry-loop bug), not real usage-limiting — comfortably above any plausible single-reader daily usage, low enough to cap runaway spend before it gets large.

## Comments

Resolved via a `/grilling` session on 2026-08-02, in the same conversation that created this map.
