# vista_comic collaboration guide

This file defines durable collaboration and engineering rules for humans, Codex, Claude, and sub-agents working in this repository. Product direction lives in `README.md`; active milestones, temporary scope, task status, and acceptance criteria live in `PLAN.md`.

## Required context

Before planning or implementing work:

1. Read `README.md` for the product vision and long-term direction.
2. Read `PLAN.md` for the active milestone, current scope, task status, dependencies, and acceptance criteria.
3. Inspect the working tree and relevant Git diff before editing.

Do not infer current progress from this file. Treat `PLAN.md` as the source of truth for execution status.

## Development rules

- Present a short plan before implementation.
- Work only within the active milestone unless the user explicitly expands the scope.
- Work in small, reviewable increments and complete shared foundations before dependent feature work.
- Prefer the minimum architecture that satisfies current acceptance criteria.
- Extract a component only when it is repeated or gives its parent a clear responsibility.
- Pass data and actions into reusable views instead of hard-coding production behavior inside them.
- Avoid broad refactors while implementing a focused feature.
- Preserve uncommitted, unrelated, and user-authored changes.
- Reuse existing assets and project conventions where practical.
- Do not commit, push, publish, or deploy unless the user explicitly requests it.

## Source-of-truth boundaries

- `README.md`: product purpose, user problem, long-term experience, and roadmap.
- `AGENTS.md`: durable collaboration rules, ownership boundaries, and verification expectations.
- `PLAN.md`: active milestone, temporary in-scope and out-of-scope items, progress, owners, dependencies, known issues, and next action.
- The current user request: task-specific details that do not need to become durable repository policy.

When these documents disagree, pause implementation, identify the conflict, and ask the coordinator to resolve the source of truth.

## Agent roles

### Coordinator

- Use the `coordinate-vista-comic` skill for milestone planning, delegation, integration, and evidence-based `PLAN.md` updates.
- Own product-level planning, integration, and task boundaries.
- Confirm that assigned work matches the active milestone in `PLAN.md`.
- Complete or define shared models, navigation contracts, sample data, and design tokens before dependent agents begin.
- Assign only independent, non-overlapping work to sub-agents.
- Integrate changes and protect the visual and architectural consistency of the app.
- Own cross-feature files and project-wide verification unless explicitly delegated.

### Feature agent

- Modify only the files and directories explicitly assigned by the coordinator.
- Consume shared models and navigation contracts without changing them unilaterally.
- Request cross-feature or shared API changes from the coordinator.
- Report completed work, verification results, assumptions, and remaining issues.

### Code reviewer

- Use the `review-vista-comic-code` skill for independent review and verification.
- Review after implementation rather than editing concurrently with the implementer.
- Prioritize correctness, navigation, state coverage, safe areas, compact layouts, Dynamic Type, dark mode, accessibility, and missing tests.
- Report concrete findings with file and location references.
- Do not modify code unless explicitly reassigned to implement confirmed fixes.

## Project skills

Each skill is authored once per agent runtime. Invoke a skill by name using the runtime's convention: Codex uses the `$name` prefix (skills under `.agents/skills/`); Claude Code uses the `/name` slash command (skills under `.claude/skills/`). Both runtimes share the same skill content and behavior.

- `coordinate-vista-comic`: coordinate active milestones, sub-agent ownership, integration, and project status.
- `review-vista-comic-code`: perform read-only code review and run evidence-based verification.
- `capture-vista-comic-progress`: record verified progress under the Notion `vista_comic` date page after the user authorizes the update.
- `ship-vista-comic`: after the user has reviewed a change and asked to publish it, verify the build, branch, commit, push, and open a pull request. Never pushes to the default branch unless explicitly overridden.

## Delegation rules

- Delegate only work that can proceed independently with clear inputs and outputs.
- Give each sub-agent an explicit owner, file boundary, acceptance criteria, and verification expectation.
- Do not let multiple agents edit the same file concurrently.
- Shared contracts are coordinator-owned unless responsibility is explicitly transferred.
- Update `PLAN.md` when ownership, dependencies, status, or the next action materially changes.

## Verification

For every implementation increment:

1. Inspect the Git diff and confirm unrelated work is unchanged.
2. Build or run relevant SwiftUI previews when the environment supports it.
3. Exercise the changed navigation path in an iOS simulator when available.
4. Check at least one compact phone layout and one larger phone layout for UI changes.
5. Verify relevant empty, loading, failure, and boundary states when required by `PLAN.md`.
6. Explain any verification that could not be completed because of environment limitations.

## Learning handoff

After implementation, explain the most relevant SwiftUI and architecture concepts in concise, guided language. Focus on why the chosen structure works, the trade-offs involved, and how the user can verify it rather than narrating every line of code.
