# Manual schema migrations

This backend has **no migration tool**. `db.init_engine` calls
`Base.metadata.create_all`, which issues `CREATE TABLE IF NOT EXISTS`: it adds a
**new table** for free, and will **never** add, drop or alter a column on an
existing one.

So any schema change that isn't a brand-new table is a manual step, run against
the deployed Postgres before the new build starts. This file is the record of
those steps.

Adopting Alembic is the right call and is deliberately deferred — see
`ROADMAP.md`'s M10 entry and the `comprehension-response-ux` map's Out of scope.
**The trigger is the step below landing**: once `comprehension_record` starts
holding data worth keeping, baseline the schema and every change after that is a
migration rather than an entry here.

## Pending

### Drop `saved_translation` (comprehension-response-ux)

`comprehension_record` replaces `saved_translation`. The new table is created
automatically; the old one has to go by hand.

**Do not run this yet.** Both tables are live during the client cutover — the
shipped app still calls `/translations` until the iOS client moves to
`/comprehensions`. Run it as part of the removal ticket, which deletes the
`/translations` routes in the same change:

```sql
DROP TABLE IF EXISTS saved_translation;
```

The rows are disposable by decision — saved vocabulary was confirmed as rarely
revisited, which is the premise for replacing it with automatic history — so
there is nothing to migrate across, only to drop.

**If this is skipped**, nothing fails loudly: `create_all` simply does nothing,
the orphaned table lingers, and the only symptom is a table no code reads. The
more dangerous variant is the reverse ordering — shipping a build whose model
expects columns an existing table lacks — which surfaces at runtime as a
"column does not exist" error that reads like a code bug rather than a missed
deployment step. That is the failure mode this file exists to prevent.
