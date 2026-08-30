---
name: devbot:improve-reviewing
description: "Improves how the reviewer reviews changesets so that issues detected by an external reviewer will be caught by our reviewer next time. Use this skill when the TeamLead orchestrator completes a PR review resolution session."
---

# Skill: Improve Reviewing from External Feedback

Analyze external review comments addressed in current session, identify gaps in our reviewer's detection capabilities, and propose improvements. The improvements land in exactly two places, by kind:

| Improvement kind                                                                                                                     | Target file                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| Reviewer **behaviour** — unique workflow, tone of voice, behavioural MUST/MUST NOT rules, skill references                           | `src/agentic/devteam/agents/reviewer.md`                    |
| What the reviewer **inspects and flags** — review checks, issue types (generic or per-technology), finding patterns, report template | `src/agentic/devteam/skills/review-implementation/SKILL.md` |

Anything that is not about reviewing stays out of both files.

## When to Apply

- When TeamLead completes a PR review resolution session and wants to improve the reviewer
- When external PR review comments reveal issues our reviewer should have caught

## Goal

Improve reviewer behaviour and/or the review skill so issues detected by external reviewer will be detected by our reviewer next time.

## Procedure

### Step 1: Collect external review issues

Gather all review comments addressed in current session. For each comment, classify:

| Field                               | Description                                                                      |
| ----------------------------------- | -------------------------------------------------------------------------------- |
| **Issue**                           | What external reviewer flagged                                                   |
| **Category**                        | Code quality, security, performance, architecture, naming, logic, testing, style |
| **Was it code change?**             | Did comment result in code change or just explanation?                           |
| **Should our reviewer catch this?** | Yes / No / Already covered                                                       |

Filter to only issues where **should our reviewer catch this = Yes** and **already covered = No**.

### Step 2: Identify target files

For each gap, determine which file(s) need changes:

| Target                                                      | When                                                                                                                      |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `src/agentic/devteam/skills/review-implementation/SKILL.md` | New review check, new issue type (generic or per-technology), modified check, new finding pattern, report template change |
| `src/agentic/devteam/agents/reviewer.md`                    | New behavioural rule (workflow, tone, MUST/MUST NOT), new skill reference                                                 |
| Other reviewer-referenced skills                            | If gap falls within an existing skill's scope                                                                             |

Read target files before proposing changes.

### Step 3: Draft improvements

For each gap, draft concrete change:

- **New review check or issue type** — add to `review-implementation/SKILL.md`. Generic findings (apply to any stack) go under `## Recurring issue types → ### Generic`; stack-specific findings go under `## Recurring issue types → ### Technology-specific → #### <technology>` (PHP, Laravel, Kubernetes, … — use an existing list or create one for the technology). Follow the existing pattern: numbered heading, bullet list of checks, expected property.
- **Strengthened existing check or issue type** — extend the existing section in `review-implementation/SKILL.md` with additional verification steps.
- **New behavioural MUST/MUST NOT rule** — add to `reviewer.md` if the rule governs reviewer behaviour (workflow, tone, what the reviewer does), not what it inspects.
- **New skill reference** — add to reviewer's Skills section if new skill covers gap.

### Step 4: Present suggestions for approval

Present each suggestion to human stakeholder:

> ### Suggestion N: \<title\>
>
> **External review issue**: \<what external reviewer flagged\>
>
> **Gap**: \<why our reviewer didn't catch it\>
>
> **Target file**: \<path\>
>
> **Change**: \<description of change\>
>
> **Rationale**: \<why this will prevent gap next time\>

Ask approval per suggestion: **Approve**, **Modify**, or **Skip**.

### Step 5: Implement approved suggestions

For each approved suggestion:

1. Apply changes to target files.
2. Verify structural consistency — YAML frontmatter, heading hierarchy, numbering sequence.
3. Record as decision in `latent/PDRs/` or `latent/ADRs/` following `devbot:memory-management` skill routing (section 2).
4. Commit: `git add <specific-files>`, verify with `git diff --staged --stat`, commit with descriptive message.

### Step 6: Summary

> ### Improve Reviewing Summary
>
> **External review comments analyzed**: N
> **Gaps identified**: N
> **Suggestions proposed**: N
> **Approved**: N / **Skipped**: N / **Modified**: N
>
> #### Changes applied
>
> - \<file\>: \<one-line description\>

## Scope Boundaries

### In scope

- Changes to `src/agentic/devteam/agents/reviewer.md` (behaviour, workflow, tone, skill references)
- Changes to `src/agentic/devteam/skills/review-implementation/SKILL.md` (review checks, issue types, report template)
- Changes to other skills referenced by the reviewer agent
- Adding new skills if a review capability is entirely missing

### Out of scope

- Production code changes
- Changes to non-reviewer agents or skills
- Changes to files with "no-vcs" in the name

## MUST

- Read target files before proposing changes.
- Present each suggestion individually for approval.
- Preserve existing file structure and formatting conventions.
- Route each gap to the right target by kind: behaviour → `reviewer.md`, inspection → `review-implementation/SKILL.md`.
- Only propose changes that address actual gaps — do not add redundant checks.

## MUST NOT

- Apply changes without explicit approval.
- Modify production code.
- Remove existing review checks or weaken existing rules.
- Add checks that duplicate what's already covered.
- Put inspection content (issue types, checks) in `reviewer.md`, or behavioural rules (workflow, tone) in `review-implementation/SKILL.md`.
