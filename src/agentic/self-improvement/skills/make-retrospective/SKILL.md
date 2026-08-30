---
name: devbot:make-retrospective
description: "Evaluates the quality of completed work and runs post-iteration retrospectives. Use this skill after completing a task or iteration to assess quality, capture metrics, and identify process improvements."
---

# Skill: Evaluation and Monitoring

Structured quality evaluation of completed work and post-iteration retrospectives. Ensures quality assessed systematically, not just through "tests pass and reviewer approved."

## When to Apply

- After completing an implementation task (post-task evaluation)
- After completing all tasks in a backlog (post-iteration retrospective)
- When the orchestrator needs to assess whether delivered work meets quality standards

## Honesty gate (MUST)

Every claim in retrospective about deliverable, agent action, or workflow event MUST cite either:

1. **Artefact's path AND verifying observation** (line number, content excerpt) author obtained via `read`, OR
2. **Absence of expected artefact**, confirmed via `glob` or `ls` (cite empty-result tool call).

Retrospective MUST NOT make causal claims about subagent behaviour ("critic hallucinated", "architect skipped X", "PO over-scoped Y") without citing artefact demonstrating behaviour. If behaviour asserted missing, assertion MUST cite tool call (`grep`, `glob`, `read`) whose result consistent with absence claim.

**Format requirement**: each "what went wrong" claim in retrospective MUST include parenthetical citation in form `(per <path>:<line> | per <tool-call-result>)`. Example:

> "Architect skipped Pre-[FINISHED] Hygiene Gate (per `interactions.md:42` showing [FINISHED] signal without prior hygiene-report file; per `glob 'storage/.../iteration-N/.ai/.../hygiene-*.md'` returning no matches)."

**Validation**: retrospective entry without supporting citation is invalid. Retrospective author (orchestrator) MUST either support claim with citation or remove before filing. Orchestrator MUST NOT defer this check to later iteration's quality-report — gate fires at retrospective-write time.

### Per-Agent count claims (MUST)

Every "total invocations" or per-agent count claim in retrospective MUST cite source of count: either `(per interactions.md Per-Agent Totals table)` or `(per delegation_count: X PO + Y architect + ...)` with underlying counts from `interactions.md`. Counts not citing source-of-truth are invalid. Retrospective author MUST run Per-Agent reconciliation procedure (per `plan` SKILL Step 8 `Per-Agent Totals reconciliation across all closing artefacts`) before writing any agent-count claim.

**Prose-vs-table cross-check (MUST)**: Every numeric claim in retrospective free-prose (paragraphs, bullets, "What Went Well" / "What Needs Improvement" / "Process Observations") about agent count, invocation count, stall count, critic-round count, re-delegation count, or task count MUST match corresponding cell in reconciliation table or be flagged with inline `[reconciliation-note: <one-line rationale>]` tag explaining discrepancy (e.g. `[reconciliation-note: prose excludes rejected critic R1 first attempt; table includes it per Per-Agent Totals procedure]`).

Retrospective author MUST run prose-vs-table cross-check before filing: for each numeric claim in free-prose that names count category (agent, invocation, stall, critic-round, re-delegation, task), look up same category in reconciliation table and confirm values match (or inline `[reconciliation-note:]` tag explains divergence). Counts in free-prose without either match or tag are invalid.

**Validation**: retrospective with prose count `K` and table count `K' ≠ K` for same category, without `[reconciliation-note:]` tag bridging two, is invalid. Either prose number must be corrected to match table, or divergence explained inline. Orchestrator MUST NOT defer this check to later iteration's quality-report — gate fires at retrospective-write time.

## Post-Task Quality Rubric

After each task is implemented, reviewed, and committed, the orchestrator evaluates it against this rubric:

| Dimension               | Question                                                           | Rating                                    |
| ----------------------- | ------------------------------------------------------------------ | ----------------------------------------- |
| **Plan Adherence**      | Does the implementation match what the Architect's plan specified? | FULL / [PARTIAL] / DEVIATED               |
| **Acceptance Criteria** | Are all acceptance criteria met and tested?                        | ALL / SOME / NONE                         |
| **Test Coverage**       | Are happy paths, failure paths, and edge cases covered?            | COMPLETE / ADEQUATE / GAPS                |
| **Code Quality**        | Does the code follow project conventions and pass static analysis? | CLEAN / MINOR_ISSUES / SIGNIFICANT_ISSUES |
| **Documentation**       | Are new patterns, configs, or APIs documented where needed?        | COMPLETE / [PARTIAL] / MISSING            |

### Quick Rating

- **All FULL/ALL/COMPLETE/CLEAN** = task delivered cleanly, no follow-up needed.
- **Any [PARTIAL]/ADEQUATE/MINOR_ISSUES** = acceptable but note for improvement in memories.md.
- **Any DEVIATED/NONE/GAPS/SIGNIFICANT_ISSUES/MISSING** = follow-up task required before moving on.

## Post-Iteration Retrospective

After all tasks in backlog completed (`devbot:implement-story` skill step 3), orchestrator produces retrospective:

### Procedure (MUST follow in order)

1. Write retrospective to `<issue-folder>/retrospective/planning.md` or `<issue-folder>/retrospective/implementation.md` using the template below.
2. **Immediately** load and execute the `devbot:address-retrospective` context skill with the retro file path. This step is NOT optional and MUST NOT be deferred. Retrospective is incomplete until `devbot:address-retrospective` has run.
3. Report completion to stakeholder only after both steps above are done.

**Gate**: If step 2 is skipped, the retrospective is [PARTIAL] — not [FINISHED]. Orchestrator MUST NOT signal [FINISHED] until `devbot:address-retrospective` has been invoked.

### Template

Save to `<issue-folder>/retrospective/planning.md` or `<issue-folder>/retrospective/implementation.md`.

> # Retrospective
>
> **Iteration**: <issue-folder name>
> **Date**: YYYY-MM-DD
> **Tasks completed**: N / M
>
> ## Quality Summary
>
> | Task   | Plan Adherence | Acceptance Criteria | Test Coverage | Code Quality | Documentation |
> | ------ | -------------- | ------------------- | ------------- | ------------ | ------------- |
> | Task 1 | FULL           | ALL                 | COMPLETE      | CLEAN        | COMPLETE      |
> | Task 2 | ...            | ...                 | ...           | ...          | ...           |
>
> ## What Went Well
>
> - <thing-that-worked>
>
> ## What Needs Improvement
>
> - <thing that could be better>
> - **Action**: <concrete change to make> — record in memories.md under the appropriate category.
>
> ## Process Observations
>
> - **Re-delegations**: How many times was work re-delegated due to stalled sessions?
> - **Review iterations**: Average number of Reviewer -> Developer round-trips per task.
> - **Escalations**: How many escalations occurred and to whom?
> - **Blockers**: What blocked progress and how was it resolved?
>
> ## Follow-Up Tasks
>
> _If none: "No follow-up tasks."_
>
> - <follow-up task description>

## Monitoring During Implementation

Orchestrator should track these signals during implementation (no formal report needed — just awareness):

- **Iteration velocity** — Are later tasks taking longer than earlier ones? May indicate context overflow or growing complexity.
- **Review rejection rate** — Are most reviews requesting changes? May indicate unclear plans or insufficient delegation context.
- **Test failure rate** — Are developers spending most time fixing tests rather than implementing? May indicate tests written with incorrect assumptions.
- **Escalation frequency** — Are agents frequently escalating? May indicate plans need more detail.

If any signal trends negatively across 3+ tasks, orchestrator should pause and address root cause before continuing.

## MUST

- `devbot:address-retrospective` MUST be invoked as step 2 of the Post-Iteration Retrospective procedure — not after, not deferred, not optional. Skipping it makes the retrospective [PARTIAL].
- `devbot:address-retrospective` MUST process all three retro sections: **What Needs Improvement**, **Process Observations**, and **Follow-Up Tasks**. Explicitly acknowledge each section — even if no actionable items exist, state "No actionable items" rather than silently skipping.
