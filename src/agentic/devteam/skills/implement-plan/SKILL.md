---
name: devbot:implement-plan
description: "Executes implementation plan steps systematically. Use this skill whenever implementing an architect's plan step-by-step, signalling completion, and handling review feedback."
---

# Skill: Plan Execution

Systematic process for implementing architect's plan one step at a time, signalling completion, and responding to review feedback.

## When to Apply

- Implementing architect's plan into production code
- Plan reached FINAL status and ready for implementation

## Step Completion Protocol

Complete plan one step at a time:

1. **Find precedent** — Before writing new code, find and follow closest existing implementation.
2. **Implement** — Write code specified in plan step.
3. **Test** — Run test suite. Fix failures introduced by this step before moving on.
4. **Format** — Run project's formatter (`make cs`) for any source files touched in this step. Stage formatter corrections together with step's changes — they belong in same commit, not orphaned in working tree for someone else to discover.
5. **Commit** — Only after tests pass and formatter output clean. Use `git add <specific-files>` (never `git add -A` or `git add .` from repository root), verify `git diff --staged --stat`, then commit referencing task and step (e.g. `[TASK-123] Step 3: Add CreateOrder command handler`). **Task is not finished until committed.**

If step fails in way suggesting plan is wrong (not coding mistake), do not redesign. Escalate.

## Signalling Completion

When all steps implemented and tests pass:

1. Record brief summary in `<issue-folder>/DONE.md`: steps completed, test suite result, open questions or caveats.
2. This signals Reviewer task ready for review.

## Handling Review Feedback

- **BLOCKER**: Must fix. Implement fix, re-run tests, commit, update `DONE.md`.
- **WARNING**: Should fix. Same process, unless you believe finding incorrect — respond using `Question:` / `Answer:` / `Rationale:` format.
- **INFO**: Consider fixing. No response required if choose not to act.

After addressing feedback, update `DONE.md` to signal re-review readiness.
