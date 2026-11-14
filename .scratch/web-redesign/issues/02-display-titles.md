Status: ready-for-agent

# 02 Backend: displayTitle from title.txt

Spec: ../spec.md (Wire contract)

## What
- Scanner reads `title.txt` in each comic folder (first non-blank line, trimmed; missing/unreadable/blank → null).
- `displayTitle` on `ComicSummary` and `ComicDetail`. `title` unchanged.
- Web: add `displayTitle: string | null` to `web/src/api/types.ts` only (pages use it in their own tickets).

## Acceptance
- Backend tests cover present / missing / blank / whitespace / multi-line; existing tests pass.

Blocked by: none

