---
name: audit-codebase
description: "Audits a codebase for pattern drift, inconsistencies, and architectural erosion. Use this skill whenever you need a holistic review of codebase health rather than a single-changeset review — e.g. 'audit the codebase', 'check for drift', 'is the architecture eroding', or onboarding to a codebase that has drifted over time."
---

# Skill: Codebase Audit

Detect pattern drift, inconsistencies, and architectural erosion holistically across codebase — not scoped to single changeset (that is reviewer's job).

## When to Apply

- Requested by stakeholder, another agent, or as part of milestone review
- Performing holistic assessment of codebase health and consistency

## Inputs

- Full codebase
- Architecture document
- ADR log

## Audit Report

Save to `<issue-folder>/AUDIT-YYYY-MM-DD-NNN.md`.

### Template

> # Codebase Audit Report
>
> **Scope**: What audited.
>
> ## Strengths
>
> Patterns consistently applied and working well.
>
> ## Findings
>
> _If none: "No findings. Codebase is consistent."_
>
> ### Finding <n>: <Title>
>
> - **Severity**: CRITICAL | IMPORTANT | MINOR
> - **Pattern**: Convention or rule being violated.
> - **Evidence**: File paths and line numbers (at least two data points).
> - **Problem found**:
> - **Why it matters**:
> - **Recommendation**: Specific, incremental fix (never wholesale rewrite).
>
> ## Tools used
>
> ### SKILLS
>
> List skills used by agent while creating report, or "None."
>
> ### MCP tools
>
> List MCP tools used by agent while creating report, or "None."

### Severity Definitions

- **CRITICAL** — Causes bugs, data corruption, or fundamental confusion.
- **IMPORTANT** — Will cause problems at scale or under growth.
- **MINOR** — Cosmetic/stylistic inconsistency with no functional impact.

When in doubt between severities, choose higher one.
