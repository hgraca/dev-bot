---
name: review-plan
description: "Reviews an architect's implementation plan for correctness, completeness, and architectural consistency. Use this skill whenever evaluating a draft plan before code is written."
---

# Skill: Plan Review

Evaluate architect's implementation plan for correctness, completeness, and architectural consistency before any code written.

## When to Apply

- Architect sends draft plan for review
- Evaluating whether plan is ready for implementation

## Inputs

- Architect's plan (path or inline content)
- Brief
- Architecture document
- ADR log

## Procedure

### Step 1: Read the plan — MUST

Before writing the review, read the plan file. The delegation prompt provides at minimum the plan's file path (canonical `<issue-folder>/backlog.md`). The plan content may also be embedded inline in the prompt — if so, use it directly. If only the path is provided, read the file at that path before proceeding. The review must cite specific line numbers and sections from the plan (see Template: Evidence field); this is impossible without reading the file.

If the plan content is neither embedded nor reachable at the provided path, signal `[BLOCKED] plan_not_accessible — provide plan content inline or verify file path` and do not proceed.

### Step 2: Write the review

Proceed to write the review report below. All subsequent steps assume the plan has been read and its content is available for citation.

## Plan Review Report

### Mandatory output filename — MUST

Save review to `<issue-folder>/PLAN-REVIEW-YYYY-MM-DD-NNN.md`. Where:

- `YYYY-MM-DD` is current UTC date.
- `NNN` is zero-padded 3-digit sequential number, scoped to same issue folder. List existing `PLAN-REVIEW-*.md` files in folder and use next available number; start at `001`.

Do **not** use any other prefix (no `CRITIC-*.md`, no `REVIEW-*.md`, no `critic-feedback.md`). Orchestrator and downstream tooling locate review files by `PLAN-REVIEW-` prefix; deviating breaks task-resumption flows and architect's "address feedback" loop.

If previous review with same date+number already exists, do not overwrite — bump `NNN`. Each iteration of critic loop produces new file.

### Template

> # Plan Review Report
>
> **Verdict**: APPROVED | CHANGES REQUESTED
>
> Plan APPROVED when contains zero BLOCKER findings.
>
> ## Strengths
>
> What works well. Reference step numbers and design choices.
>
> ## Findings
>
> _If none: "No findings. Plan is sound."_
>
> ### Findings summary
>
> | #    | Title                  | Location            | Severity                      |
> | ---- | ---------------------- | ------------------- | ----------------------------- |
> | <NN> | <one_line_description> | <where_in_the_plan> | <BLOCKER,WEAKNESS,SUGGESTION> |
>
> ### Finding <n>: <Title>
>
> - **Category**: Weakness | Suggestion | Blocker
> - **Severity**: CRITICAL | IMPORTANT | MINOR
> - **Evidence**: File paths, line numbers, or plan step references.
> - **Problem found**:
> - **Why it matters**:
> - **Recommendation**:
> - **Workflow gap** _(optional)_: If this finding represents _class_ of failure not prevented by workflow (cross-artefact drift, recurring type leak, repeated rule violation across artefacts, same defect category across multiple findings in this review), name rule that should exist and which file should host it. Leave blank if finding is one-off.

### Category and Severity

- **Blocker** — Always CRITICAL. Must resolve before approval.
- **Weakness** — CRITICAL or IMPORTANT. Concrete problem that will cause issues.
- **Suggestion** — IMPORTANT or MINOR. Improvement opportunity.

When in doubt between severities, choose higher one.

### Third-party library citation in recommendations — MUST

When recommendation involves third-party library — namespace, class name, method signature, configuration option — critic MUST cite source-of-truth for API in recommendation itself. Acceptable cites same as in `make-plan` SKILL's "Third-party library integration" section:

- library's `composer.json` autoload section with file path + line reference, OR
- specific class file in vendor tree with file path + class name, OR
- library's official README or documentation URL with symbol name visible at that URL.

Hypothetical recommendations forbidden — if cannot verify API surface, finding should describe problem and require architect to verify, NOT propose specific replacement (e.g. "cited namespace is unverified — architect must verify against vendor's `composer.json` before re-submission" rather than "use `Approve\Approvals` instead").

This rule symmetric with architect-side rule in `make-plan` SKILL. Together they form closed loop: architect must cite when proposing; critic must cite when recommending.
