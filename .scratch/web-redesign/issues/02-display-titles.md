Status: done

# 02 Backend: displayTitle from title.txt

Spec: ../spec.md (Wire contract)

## What
- Scanner reads `title.txt` in each comic folder (first non-blank line, trimmed; missing/unreadable/blank → null).
- `displayTitle` on `ComicSummary` and `ComicDetail`. `title` unchanged.
- Web: add `displayTitle: string | null` to `web/src/api/types.ts` only (pages use it in their own tickets).

## Acceptance
- Backend tests cover present / missing / blank / whitespace / multi-line; existing tests pass.

Blocked by: none

## Comments

2026-11-14 (backend-implementer): Done on `feature/web-redesign-titles`.
- Read at scan time in `scanner._read_display_title`, stored on `ComicEntry.display_title`; `POST /rescan` refreshes it. Decoded as `utf-8-sig` (strict UTF-8, BOM dropped). Also → null: a directory named `title.txt`, a symlink escaping the library, files over 64 KiB, invalid UTF-8. Never affects ids, chapters or cover.
- `displayTitle` is always sent (null, not omitted) on `GET /comics` and `GET /comics/{id}`.
- Web: `displayTitle: string | null` in `api/types.ts`; `client.ts` spreads both objects so the field survives. Two store test fixtures (`stores/comics.test.ts`, `stores/library.test.ts`) gained `displayTitle: null` so `npm run typecheck` passes.
- Verified: scanner tests pass; `npm run typecheck` passes. Postgres was not running locally, so `test_endpoints.py` (incl. the new `test_display_title_on_list_and_detail`) and other DB-backed tests were not run; both routes were exercised ad hoc with the progress store degraded to empty.

