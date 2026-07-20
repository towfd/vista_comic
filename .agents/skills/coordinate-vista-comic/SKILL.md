---
name: coordinate-vista-comic
description: Coordinate milestone work in the vista_comic repository. Use when Codex needs to select or start the active milestone, break work into tasks, define ownership and dependencies, delegate non-overlapping work to sub-agents, integrate results, or update PLAN.md after verified progress.
---

# Coordinate vista_comic

Coordinate work from the repository's sources of truth without replacing them with assumptions from the current conversation.

## Establish context

1. Read `README.md`, `AGENTS.md`, and `PLAN.md` from the repository root.
2. Inspect `git status` and the relevant diff before planning edits.
3. Identify the active milestone, scope, acceptance criteria, dependencies, protected work, and open decisions.
4. Stop and surface conflicts between the user request and repository documents before implementation.

## Plan the increment

1. Define one reviewable outcome tied to the active milestone.
2. Separate coordinator-owned shared contracts from feature-owned implementation.
3. Identify the minimum files likely to change.
4. Define observable acceptance criteria and proportionate verification.
5. Present a concise plan before implementation.

Do not introduce future architecture that is outside the active milestone.

## Delegate safely

Delegate only independent work that can proceed with stable inputs.

For every sub-agent assignment, provide:

- objective and expected outcome;
- allowed file or directory boundary;
- shared contracts it must consume but not change;
- acceptance criteria;
- required verification;
- required handoff summary.

Do not let two agents edit the same file concurrently. Keep shared models, routes, design tokens, and integration changes coordinator-owned unless ownership is explicitly transferred.

## Integrate and verify

1. Review every returned diff before integration.
2. Confirm unrelated user changes remain intact.
3. Run the builds, tests, previews, or simulator checks required by `AGENTS.md` and `PLAN.md`.
4. Use `$review-vista-comic-code` after implementation when an independent verification pass is warranted.
5. Send confirmed findings back to the original owner when possible.

## Maintain project state

Update `PLAN.md` only from evidence:

- mark a task complete only after its acceptance criteria are met;
- record blockers and environment limitations explicitly;
- update owners or dependencies when assignments change;
- keep exactly one clear next action;
- never report a milestone complete while required work remains.

After a meaningful verified checkpoint, use `$capture-vista-comic-progress` when the user requests or has authorized a Notion progress update.

## Handoff

Report:

- outcome and affected milestone;
- files changed by owner;
- verification performed and results;
- unresolved findings or blockers;
- `PLAN.md` status changes;
- next action.
