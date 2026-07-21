---
name: ship-vista-comic
description: Ship reviewed vista_comic changes as a pull request. Use when the user has personally reviewed the change and asks Codex to push, ship, publish, or open a PR. Creates a feature branch, verifies the build, commits with project conventions, pushes, and opens a PR. Never pushes to the default branch unless the user explicitly overrides.
---

# Ship vista_comic

Turn reviewed, verified work into a pull request. This skill is the sanctioned
path for publishing vista_comic changes to the remote. It defaults to a feature
branch and a pull request; it never commits or pushes to the default branch
unless the user explicitly overrides.

## Authorization gate

Proceed only when both are true:

1. The user explicitly asked to ship, push, publish, or open a PR for this change.
2. The user has personally reviewed the change, or explicitly delegates that review in the same request.

If either is missing, stop and ask. Never publish unrequested or unreviewed work.

## Establish state

1. Read `PLAN.md` to name the milestone or change being shipped.
2. Inspect `git status` and the full diff.
3. Confirm the diff contains only intended work; preserve unrelated and uncommitted user changes.
4. Identify anything that must not be published (see Exclusions).

## Verify before shipping

Run the narrowest relevant checks the environment supports, and require them to pass:

- Xcode build for the `vista_comic` scheme;
- any focused tests relevant to the change.

Do not ship a failing or unverified build. Record exact environment limitations separately; never present a skipped check as success.

## Exclusions

Never stage or commit:

- `.claude/settings.local.json` or any per-user local settings;
- secrets, tokens, credentials, or `.env` files;
- build output (`DerivedData/`, `build/`) or Xcode user state.

Confirm the staged file list before committing.

## Branch and commit

1. Update the local default branch, then branch from it: `ship/<short-topic>` or `feature/<milestone>`.
2. Never commit directly to the default branch in this flow.
3. Group changes into logical, reviewable commits rather than one mixed commit.
4. Write imperative commit subjects with a short body explaining why.
5. End every commit message with the co-author trailer the runtime specifies, for example:
   `Co-Authored-By: Claude <noreply@anthropic.com>`

## Open the pull request

1. Push the branch to `origin`.
2. Open a PR with `gh pr create`.
3. PR title: a concise summary of the change.
4. PR body: scope, key changes, verification results, affected milestone, and known follow-ups.

If the repository has no GitHub remote, stop and report; do not invent a PR.

## Report

Return:

- branch name and PR URL;
- commits created;
- verification performed and its results;
- files deliberately excluded;
- suggested next action (typically: request a human merge).
