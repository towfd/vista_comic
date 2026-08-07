# Manual schema migrations

> **This file is closed.** Alembic owns the schema as of 2026-08-07 — see
> `.scratch/alembic-adoption/spec.md`. Schema changes are migrations now:
> `alembic revision --autogenerate -m "..."`, read what it produced, commit it,
> rebuild. The app runs `alembic upgrade head` itself on startup, so there is
> nothing left to remember and nothing new to add below.
>
> What remains here is the record of the era before that, kept because the
> **one-time stamp** at the bottom is the step that connects the two.

The backend used to have no migration tool. `db.init_engine` called
`Base.metadata.create_all`, which issues `CREATE TABLE IF NOT EXISTS`: it adds a
**new table** for free, and will **never** add, drop or alter a column on an
existing one.

So any schema change that wasn't a brand-new table was a manual step, run
against the deployed Postgres before the new build started. This file was the
record of those steps.

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


## The step that closed this file

### Baseline the deployed database onto Alembic — 2026-08-07

`alembic upgrade head` on a database that already has the tables would fail on
creating them, and `progress` holds reading progress that would hurt to lose. So
the deployed database is **marked** as already at the baseline revision instead
of running it:

```bash
docker compose exec api alembic stamp head
```

**Ordering is load-bearing, and stricter than it looks.** The stamp has to
happen *before* a container built from the new image starts serving. A container
that starts unstamped tries to run the baseline against tables that exist, the
migration fails, and — by the deliberate policy in `lifespan` — the container
fails hard rather than serving with a schema it cannot vouch for. That is the
designed behaviour, not a bug, but it means the sequence is:

1. Rebuild the image without starting it: `docker compose build api`
2. Stamp through a one-off container: `docker compose run --rm api alembic stamp head`
3. Start normally: `docker compose up -d api`

Safe to check first, and safe to repeat: stamping writes one row to
`alembic_version` and touches no table of the app's own.

Verified afterwards with `SELECT * FROM alembic_version;` returning the baseline
revision, and the API starting clean.
