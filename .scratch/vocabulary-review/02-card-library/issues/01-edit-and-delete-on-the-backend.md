# 01 — Edit and delete on the backend

**What to build:** The two routes the workshop needs. Nothing user-visible when this lands.

```
PATCH  /cards/{id}   -> body {translation?, kind?}; 200 with the updated card, 404 if unknown
DELETE /cards/{id}   -> 204, 404 if unknown
```

It goes first because it is the only part of this stage that can be **fully verified without a device**, and because the screen that follows is only worth building once the operations behind it are known to work.

**`PATCH` accepts exactly two fields, and refusing the rest is the point.** Source text is half of the card's identity (`../../01-card-storage/spec.md`): changing it could collide with another card under the unique constraint, and would detach the row from the `comic_id`/`chapter_id`/`page_number` still pointing at where that exact line was read. Target language is the other half. The source reference is a fact about the past. A field that is accepted and then quietly changes which card this *is* would be a trap for whoever touches this next, so the state machine stays on the server.

**A null `kind` is a legitimate value, not a missing one.** Cards collected before ticket 06 have none, and the reader must be able to clear a wrong answer as well as set one. That means telling "field absent" apart from "field present and null" — the one place in this feature where the distinction carries meaning.

**Deleting is a real delete.** Archiving was considered and dropped: a word on the ladder's top rung is already scheduled once every 60 days, which is what "I know this one" would have meant, so a second concept expressing the same thing would have had no consumer. `archived_at` stays in the schema, unused.

**Blocked by:** nothing.

**Status:** not started.

- [ ] `PATCH /cards/{id}` updates the translation and returns the whole card
- [ ] `PATCH` updates the kind, and accepts an explicit null to clear one
- [ ] `PATCH` with neither field is refused rather than silently doing nothing
- [ ] `PATCH` rejects an unrecognised kind
- [ ] `PATCH` cannot change source text, normalised key, target language, or the source reference — asserted, not assumed
- [ ] `PATCH` does not touch `ladder_stage`, `due_on`, `lookup_count` or `created_at`
- [ ] `PATCH` on an unknown id is 404
- [ ] `DELETE /cards/{id}` removes the row and returns 204
- [ ] `DELETE` twice is 404 the second time
- [ ] After a delete, collecting the same line again creates a **new** card with a fresh lookup count
- [ ] Both routes surface a store failure as 503, matching the resource's existing shape
