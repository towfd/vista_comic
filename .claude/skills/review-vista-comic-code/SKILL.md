---
name: review-vista-comic-code
description: Perform an independent, evidence-based code review and verification pass for vista_comic changes. Use after implementation, before accepting a milestone, or whenever the user asks to review a diff, validate SwiftUI behavior, run relevant builds or tests, find regressions, or assess whether acceptance criteria are satisfied.
---

# Review vista_comic code

Review as an independent Code reviewer. Default to read-only work: do not edit code, update `PLAN.md`, or implement fixes unless explicitly reassigned after reporting findings.

## Establish the review scope

1. Read `README.md`, `AGENTS.md`, and `PLAN.md`.
2. Inspect `git status`, the complete relevant diff, and surrounding code needed to understand behavior.
3. Identify the milestone acceptance criteria and the files owned by each implementer.
4. Distinguish new findings from pre-existing or unrelated working-tree changes.

## Review priorities

Prioritize substantive issues over style preferences:

1. build failures, crashes, data loss, or broken navigation;
2. incorrect behavior and regressions;
3. SwiftUI state, identity, lifecycle, and data-flow mistakes;
4. async races, resource leaks, and missing error handling;
5. first and last item boundaries, empty, loading, and failure states;
6. safe areas, compact layouts, Dynamic Type, dark mode, and accessibility;
7. missing tests that allow a realistic regression to pass unnoticed;
8. unnecessary complexity that materially increases maintenance risk.

Do not report personal formatting preferences without a concrete risk.

## Verify with evidence

Run the narrowest relevant checks supported by the environment:

- Xcode build for the active scheme;
- focused unit or UI tests;
- SwiftUI previews;
- simulator navigation for changed flows;
- compact and larger iPhone layouts for UI changes.

Do not claim a check passed unless it actually ran. Record exact environment limitations separately from product defects.

## Report findings

List findings first, ordered by severity:

- **P0 — Critical:** blocks use or risks destructive loss;
- **P1 — High:** likely crash, broken core flow, or serious regression;
- **P2 — Medium:** incorrect edge behavior or meaningful maintainability risk;
- **P3 — Low:** concrete minor issue worth fixing.

For each finding include:

- severity and concise title;
- absolute or repository-relative file path and tight line location;
- evidence and the condition that triggers the problem;
- user or engineering impact;
- specific correction direction;
- missing test when relevant.

After findings, report verification commands and results, remaining uncertainty, and whether the reviewed acceptance criteria are satisfied.

If no actionable issue is found, say so explicitly and still identify verification gaps or residual risk. Do not approve work solely because a build passes.
