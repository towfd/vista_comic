# vista_comic Claude collaboration guide

This file defines the durable collaboration and engineering rules Claude Code must follow when working in this repository. Product direction lives in `README.md`; active work (specs and tickets) lives as local markdown under `.scratch/`; `ROADMAP.md` is a milestone roadmap/history, not the live task tracker.

Claude is both a development partner and a programming tutor. Implement work within the active ticket/spec, verify it with concrete evidence, and explain the most relevant SwiftUI and architecture concepts after implementation.

## Required context

Before planning or implementing work:

1. Read `README.md` for the product vision and long-term direction.
2. Read the relevant spec/tickets under `.scratch/<feature>/` for current scope, task status, and acceptance criteria (see `docs/agents/issue-tracker.md`).
3. Consult `ROADMAP.md` for milestone history and roadmap context only — not for live status.
4. Inspect the working tree and relevant Git diff before editing.

Do not infer current progress from this file. Treat the active `.scratch/` ticket as the source of truth for execution status.

## Development rules

- Planning and approval happen up front via `/wayfinder`, `/grilling`, or the `/to-spec` → `/to-tickets` pipeline — once a spec or ticket exists from that process, proceed straight to implementation without a separate pre-implementation approval step.
- Work only within the active ticket/spec unless I explicitly expand the scope.
- Work in small, reviewable increments and complete shared foundations before dependent feature work.
- Prefer the minimum architecture that satisfies current acceptance criteria.
- Extract a component only when it is repeated or gives its parent a clear responsibility.
- Pass data and actions into reusable views instead of hard-coding production behavior inside them.
- Avoid broad refactors while implementing a focused feature.
- Preserve uncommitted, unrelated, and user-authored changes.
- Reuse existing assets and project conventions where practical.
- Free to commit and open pull requests without asking first each time — review and approval happen on the PR itself in GitHub. Never push directly to the default branch or deploy without my explicit request.

## Source-of-truth boundaries

- `README.md`: product purpose, user problem, long-term experience, and roadmap.
- `CLAUDE.md`: durable collaboration rules Claude Code must follow, ownership boundaries, and verification expectations.
- `.scratch/<feature>/`: active specs, tickets, task status, acceptance criteria, and next action — the live tracker.
- `ROADMAP.md`: milestone roadmap and history (record of what shipped). Not the live task tracker.
- `docs/agents/`: how skills consume the issue tracker (`issue-tracker.md`) and domain docs (`domain.md`).
- The current user request: task-specific details that do not need to become durable repository policy.

When these documents disagree, pause implementation, identify the conflict, and ask me to resolve the source of truth.

## Workflow

Process work runs on the installed engineering skills (Matt Pocock's methodology, available in every repo): turn a request into a spec (`/to-spec`), break it into tickets under `.scratch/` (`/to-tickets`, `/wayfinder`), implement, then review (`/code-review`) and QA (`/qa`). Use `/domain-modeling`, `/tdd`, and `/diagnosing-bugs` as the task calls for them.

The main Claude Code session drives this process, delegates implementation to the project's sub-agents, and owns integration and cross-feature consistency.

### Sub-agents (`.claude/agents/`)

- `backend-implementer`: implement one approved, reviewable backend (FastAPI / PostgreSQL / Docker / catalog) increment within an explicit file boundary.
- `frontend-implementer`: implement one approved, reviewable iOS/SwiftUI increment within an explicit file boundary.

A sub-agent modifies only the files it is assigned, consumes shared models and navigation contracts without changing them unilaterally, requests cross-cutting changes from the main session, and reports completed work, verification results, assumptions, and remaining issues.

### Project skills (`.claude/skills/`)

These cover project-specific edges the generic methodology does not:

- `/capture-vista-comic-progress`: record verified progress under the Notion `vista_comic` date page — only after progress is verified and I authorize the update. Do not mark planned or unverified work as complete.
- `/ship-vista-comic`: verify the build, branch, commit, push, and open a pull request — no need to wait for me to ask first; I review and approve on the PR. Never push to the default branch unless I explicitly override.

## Delegation rules

- Delegate only work that can proceed independently with clear inputs and outputs.
- Give each sub-agent an explicit file boundary, acceptance criteria, and verification expectation.
- Use parallel background agents for independent research, inspection, or verification when this materially reduces waiting time.
- Do not let multiple agents edit the same file concurrently.
- Do not review an increment while the implementation it depends on is unfinished.
- Shared contracts are owned by the main session unless responsibility is explicitly transferred.
- Update the active `.scratch/` ticket when scope, dependencies, status, or the next action materially changes.
- Remember that parallel agents increase token usage; do not delegate small tasks that are cheaper and clearer to complete in the main session.

## Verification

For every implementation increment:

1. Inspect the Git diff and confirm unrelated work is unchanged.
2. Build or run relevant SwiftUI previews when the environment supports it.
3. Exercise the changed navigation path in an iOS simulator when available.
4. **UI verification is mine, not yours.** Do not write XCUITest code, do not build-verify it, do not attempt to run it, and do not spend increment time deliberating whether some behaviour is assertable through the accessibility API. Instead, hand off a specific list of what I should look for on a real device — that list is the deliverable for any UI-facing behaviour a unit test cannot cover. (Separately, and regardless: this environment's simulator cannot reliably initialize XCUITest's accessibility runner — confirmed structurally broken across repeated attempts, not a configuration issue — so running them here would fail anyway.)
5. Check at least one compact phone layout and one larger phone layout for UI changes.
6. Verify relevant empty, loading, failure, and boundary states when the ticket requires them.
7. Explain any verification that could not be completed because of environment limitations.

## Learning handoff

After implementation, explain the most relevant SwiftUI and architecture concepts in concise, guided language. Focus on why the chosen structure works, the trade-offs involved, and how the user can verify it rather than narrating every line of code.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one root `CONTEXT.md` + ADRs under `docs/adr/`. See `docs/agents/domain.md`.
