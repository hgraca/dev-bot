---
name: address-retrospective
description: "Addresses retrospective findings by suggesting workflow improvements, asking for approval, and implementing approved changes. Use this skill after a retrospective is completed or via the /address-retro command."
---

# Skill: Address Retrospective

Turn retro findings into concrete workflow improvements. Parse retro file, extract improvement items, propose changes to workflow/skill/agent files, get approval per suggestion, implement approved ones.

## When to Apply

- After `make-retrospective` skill produces retro file
- When `/address-retro` command invoked with retro file path
- When orchestrator identifies actionable improvements in retrospective

## Input

Retro file path (`$1`). File follows `make-retrospective` template. Contains at minimum **What Needs Improvement** section with actionable items.

## Procedure

### Step 1: Parse retro file

Read retro file at provided path. Extract all items from:

1. **What Needs Improvement** section — each bullet = candidate improvement. Items with `**Action**:` annotation highest priority.
2. **Process Observations** section — look for patterns suggesting systemic issues (high re-delegations, review iterations, escalations, blockers).
3. **Follow-Up Tasks** section — items describing process or workflow changes (not feature work).

Ignore items about specific code changes, bugs, or feature work — those belong in backlog, not workflow improvements.

### Step 2: Analyze and propose

For each extracted improvement:

1. **Identify target files** — determine which skill, agent, or workflow file(s) need changes. Common targets:
    - `src/instructions/skills/workflow/*.md` — workflow skills
    - `src/instructions/skills/dev/**/*.md` — development convention skills
    - `src/instructions/skills/memory/**/*.md` — memory management skills
    - `src/instructions/agents/*.md` — agent role definitions
    - `src/instructions/commands/*.md` — command definitions
    - `.agents/memory/active/*.md` — bootstrap files

2. **Read target files** — understand current content before proposing changes.

3. **Draft concrete suggestion** — specify:
    - What file to change
    - What section to modify (quote existing text)
    - What new text should be
    - Why this change addresses retro finding

### Step 3: Present suggestions for approval

Present each suggestion to human stakeholder in this format:

> ### Suggestion N: \<title\>
>
> **Retro finding**: \<quote from retro file\>
>
> **Target file**: \<path\>
>
> **Change**: \<description of change\>
>
> **Rationale**: \<why this addresses finding\>

Ask approval per suggestion. Options:

- **Approve** — implement as proposed
- **Modify** — implement with requested changes
- **Skip** — do not implement

### Step 4: Implement approved suggestions

For each approved suggestion:

1. Apply change to target file(s).
2. If change affects skill referenced by agent roles, verify reference still valid.
3. Record change as decision in `latent/PDRs/` or `latent/ADRs/` following `memory-management` skill routing (section 2).
4. **Commit changeset** — use `git add <specific-files>` (never `git add -A` or `git add .`), verify `git diff --staged --stat`, then commit with descriptive message.

### Step 5: Summary

Output summary to human stakeholder:

> ### Address Retro Summary
>
> **Retro file**: \<path\>
> **Suggestions proposed**: N
> **Approved**: N
> **Skipped**: N
> **Modified**: N
>
> #### Changes applied
>
> - \<file\>: \<one-line description\>

## Scope Boundaries

### In scope

- Changes to workflow skills, agent definitions, command definitions, bootstrap files, memory management skills, and development convention skills.
- Adding new rules, constraints, steps, or guardrails to existing workflows.
- Reordering steps, adding checklists, or tightening acceptance criteria.
- Adding new skills if retro reveals missing workflow capability.

### Out of scope

- Production code changes — those go in backlog, not workflow improvements.
- Changes to MCP server configuration or Docker infrastructure.
- Changes to files with "no-vcs" in name.

## MUST

- Read target files before proposing changes — never suggest blind edits.
- Present each suggestion individually — never batch-approve.
- Preserve existing skill structure and formatting conventions (YAML frontmatter, heading hierarchy, table formatting).
- Record all approved changes as decisions.

## MUST NOT

- Apply changes without explicit approval.
- Modify production code — this skill for meta/workflow improvements only.
- Remove existing constraints or guardrails without strong justification.
- Create duplicate skills when existing skill can be extended.
