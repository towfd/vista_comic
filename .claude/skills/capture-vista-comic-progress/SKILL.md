---
name: capture-vista-comic-progress
description: Capture verified vista_comic development progress in the project's Notion workspace. Use after a completed implementation increment, code review, milestone decision, blocker, or status change when the user asks to record or synchronize progress under the Notion vista_comic page.
---

# Capture vista_comic progress

Write a concise, evidence-based progress entry under the correct Notion `vista_comic` date page without overwriting the user's existing notes.

## Load the target

Read `references/notion-target.md` before calling Notion tools. Treat an explicit request to update vista_comic progress in Notion as authorization for this scoped external write; otherwise ask before writing.

If the Notion connector is unavailable, stop and ask the user to connect it. Do not substitute a local file while claiming Notion was updated.

## Gather evidence

1. Read repository `README.md`, `CLAUDE.md`, `PLAN.md`, and the relevant `.scratch/<feature>/` spec/tickets.
2. Inspect relevant `git status` and diff summaries.
3. Collect actual build, test, preview, simulator, and code-review results.
4. Separate completed work from planned work.
5. Record blockers and environment limitations without presenting them as product defects.

Do not include secrets, tokens, private credentials, or large source-code dumps.

## Locate the date page

1. Use the Asia/Taipei date formatted as `YYYYMMDD`.
2. Fetch the configured parent page to confirm it is the `vista_comic` hub.
3. Search for the date title and confirm any match is a child of the configured parent.
4. If the date page exists, fetch it and append a new progress section; preserve all existing content.
5. If it does not exist, create it under the configured parent page.
6. Never create a duplicate date page because a search result was not fetched or its parent was not verified.

## Write the update

Use only sections supported by current evidence:

- `本次進度更新`
- `已完成`
- `變更內容`
- `驗證結果`
- `決策與理由`
- `阻礙或限制`
- `下一步`

For an existing date page, append a timestamped subsection under `本次進度更新`. Keep planned tasks under `下一步`; do not describe them as completed.

## Verify and report

Fetch the page after writing. Confirm the new section exists under the correct parent, then return:

- Notion page title and link;
- summary of information added;
- any facts omitted because they could not be verified.
