# Manual schema migrations

This backend has **no migration tool**. `db.init_engine` calls
`Base.metadata.create_all`, which issues `CREATE TABLE IF NOT EXISTS`: it adds a
**new table** for free, and will **never** add, drop or alter a column on an
existing one.

So any schema change that isn't a brand-new table is a manual step, run against
the deployed Postgres before the new build starts. This file is the record of
those steps.

**Adopting a migration tool is now triggered.** The deferral was explicitly
conditional on the step below landing (see `ROADMAP.md`'s M10 entry and the
`comprehension-response-ux` map's Out of scope), and it has: `comprehension_record`
is now the live table and holds data worth keeping. Baseline the post-drop schema,
and every schema change after that is a migration rather than an entry in this
file. Whoever picks it up should know two things: `progress` already holds data
that would hurt to lose, and `tests/conftest.py` builds the test schema through
the same `create_all` path as production, so adopting migrations without changing
that fixture leaves the tests validating a schema built a different way than the
deployed one.

## Executed

### Drop `saved_translation` (comprehension-response-ux) — 2026-08-06

`comprehension_record` replaced `saved_translation`. The new table was created
automatically; the old one had to go by hand.

Run as the last step of the removal ticket, **after** the rebuilt API (with the
`/translations` routes deleted) was confirmed live — so nothing was still reading
the table when it went:

```sql
DROP TABLE IF EXISTS saved_translation;
```

The rows were disposable by decision — saved vocabulary was confirmed as rarely
revisited, which is the premise for replacing it with automatic history — so
there was nothing to migrate across, only to drop. Two rows existed at the time.

Ordering that was actually followed, and the one to copy next time: merge the code
that stops using the table → rebuild and confirm the deployed API no longer serves
the old routes → drop.

**If this is skipped**, nothing fails loudly: `create_all` simply does nothing,
the orphaned table lingers, and the only symptom is a table no code reads. The
more dangerous variant is the reverse ordering — shipping a build whose model
expects columns an existing table lacks — which surfaces at runtime as a
"column does not exist" error that reads like a code bug rather than a missed
deployment step. That is the failure mode this file exists to prevent.
