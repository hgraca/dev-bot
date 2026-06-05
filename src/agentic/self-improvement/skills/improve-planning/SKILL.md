---
name: improve-planning
description: "Drives a continuous improvement loop for the multi-agent planning system. Generates a plan in an isolated task-solver session, evaluates it against absolute quality criteria, traces every weakness back to a specific instruction gap, and proposes edits to the agent files and their planning skills. Use this skill whenever the user says 'improve planning', 'improve planning instructions', or 'planning quality', wants the planning workflow to produce better plans, or after a planning iteration completes poorly."
---

# Improve Planning Instructions

Drives continuous improvement loop for multi-agent planning system. Generates plan in isolated task-solver session, evaluates from main session against absolute quality criteria, traces every weakness back to specific instruction gap, proposes edits to agent files (devbot, po, architect, critic) and their planning skills (`plan`, `make-plan`, `review-plan`). Use when user says 'improve planning', 'improve planning instructions', 'planning quality', or wants planning workflow produce better plans. Also use after planning iteration completes poorly.

## Architecture: Two Sessions

To avoid context contamination between solver and evaluator, this skill runs across **two distinct sessions**:

| Session                     | Role                                         | What it sees                                                                                           |
| --------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **Main session** (this one) | Evaluator + orchestrator of improvement loop | Artifacts produced by task-solver session, prior reports — never task-solver's working memory          |
| **Task-solver session**     | Runs planning workflow against kata          | Only kata description and current agent instructions — no prior iterations, no RCAs, no proposed fixes |

Main session responsible for: setup, evaluation, root-cause analysis, proposing changes, applying approved changes, and looping. Task-solver session responsible for: producing plan exactly as normal user request would.

Task-solver session runs in regular folder (not git repository). No git operations occur inside iteration folder. Orchestrator's commit and "verify @tester gate" rules from `src/instructions/agents/devbot.md` explicitly suspended in solver session via PROMPT.md.

Grader is **main-session devbot agent itself**. Evaluates solver's artifacts using absolute rubric defined below. No separate grading subagent.

### Scope of edits

**Only four agents and three skills in scope** for instruction improvements: only these participate in producing plan:

| Agents                  | Skills        |
| ----------------------- | ------------- |
| `devbot` (orchestrator) | `plan`        |
| `po`                    | `make-plan`   |
| `architect`             | `review-plan` |
| `critic`                |               |

`developer`, `reviewer`, and `tester` are **out of scope** because no implementation runs in this iteration — Phase 1 stops at FINAL plan. Their instructions affect implementation quality, not plan quality.

### Task constancy

Task is **always** Poke API kata at `references/poke-api-kata/`. Holding task constant makes grade deltas across iterations meaningful. **If kata changes, prior iterations no longer comparable** — restart from iteration 1.

---

## Workflow

### Step 0: Verify previous iteration's edits are committed

Performed in **main session**, _before_ invoking setup script.

Approved planning improvements applied and committed at **end of Step 7** of iteration that produced them (not at start of next iteration). Step 0 is verification gate, not application step:

1. Locate previous iteration's `approved-changes.md` (`storage/self-improvement/improve-planning/iteration-<n-1>/approved-changes.md`). If none exists (first iteration, or no approvals), skip rest of Step 0.
2. Confirm it has "Applied" footer with commit SHA.
3. Run `git log --oneline -1 <SHA>` to verify commit exists in current branch's history.
4. If footer missing or commit cannot be found, prior iteration not closed correctly — stop and ask user how to resolve (re-apply, skip, or abort iteration N).

If everything checks out, proceed to Step 1.

### Step 1: Run setup script

**First, ask user which model to test this iteration.** Show current default (top-level `model` in workspace `opencode.jsonc`) and previous iteration's model (if any) so user can decide whether to repeat or change. Warn that changing model invalidates grade comparisons against prior iterations and iteration must be tagged `model-change`.

Once user picks model, invoke setup script with model as first argument — script owns iteration-folder creation, project init, and applying model to planning agents:

```bash
bash src/instructions/skills/self-improvement/improve-planning/scripts/setup-iteration.sh "<chosen-model-id>"
```

The script will:

1. Determine next iteration number under `storage/self-improvement/improve-planning/`.
2. Copy `references/poke-api-kata/` into `iteration-<n>/`.
3. **Initialise iteration folder as its own git root** (`git init` inside `iteration-<n>/`). Required so opencode's config discovery stops at iteration folder and does NOT walk up and merge every outer `opencode.jsonc` (would poison session with secret references that don't resolve).
4. Run `devbot init` against iteration folder with project-side memory ownership (`DEVBOT_MEMORY_OWNER=project`).
5. Materialise `iteration-<n>/opencode.jsonc` (replace symlink with real file).
6. Apply model passed as `$1` to four planning agents (`devbot`, `po`, `architect`, `critic`) in iteration's `opencode.jsonc`. (If no argument AND stdin is TTY, script falls back to prompting user; if no argument AND no TTY, script fails loudly.)
7. **Materialise symlinked `.opencode/agents/devbot/` directory into real directory of copies, then rewrite `model:` frontmatter on four planning agents to chosen model.** Required because agent-file frontmatter `model:` overrides `agent.<name>.model` setting in `opencode.jsonc`, and symlink target lives in shared `src/instructions/agents/` tree (must not edit globally).
8. Print instructions for user to start new opencode session inside iteration folder.

#### Setup script failure recovery

If script fails partway through:

1. **Diagnose and fix** immediate cause (missing dependency, permission issue, malformed JSONC, etc.).
2. **Roll back partial iteration folder**: `rm -rf storage/self-improvement/improve-planning/iteration-<n>/` so retry starts clean.
3. **Re-run script** from scratch.
4. **If you cannot diagnose or fix** failure, stop and ask user for instructions before doing anything else. Do not leave partial iteration folder behind.

After the script succeeds, write `iteration-<n>/metadata.json`:

```json
{
  "iteration": <n>,
  "timestamp": "<ISO 8601>",
  "model": "<chosen model id>",
  "rubric_version": "<version from this file>"
}
```

**Warn user** if chosen model differs from previous iteration — grade deltas across model changes not meaningful and iteration must be tagged `model-change` in tracker.

### Step 1.5: Task-solver session runs

User opens new opencode session in `iteration-<n>/` and tells agent: _"Execute instructions in PROMPT.md"_. That prompt instructs solver to run Phase 1 (planning only — no implementation) and Phase 2 (write `interactions.md`) end-to-end **without asking human stakeholder for approvals**. When solver finishes, it instructs user to return to main session and say "evaluate this iteration".

Solver follows standard `plan` workflow, creating normal **issue-folder** under:

```
iteration-<n>/.agents/memory/work/active/<YYYYMMDD-HHMMSS-NN>-<slug>/
```

This issue-folder referred to below as `<issue-folder>`. Locate by globbing `iteration-<n>/.agents/memory/work/active/*/` — exactly one match expected. If zero or more than one, treat as solver failure (record in `iteration-<n>/handoff-failure.md`).

Required artifacts inside `<issue-folder>` after solver finishes:

- `backlog.md`
- `PLAN-ARCH-*.md` (architect's combined architecture spec + implementation plan)
- `PLAN-REVIEW-*.md` (critic review)
- `summary.md` (planning summary)
- Any UI/UX specs
- `interactions.md`

Main-session evaluation artifacts (`metadata.json`, `quality-report.md`, `root-cause-analysis.md`, `proposals.md`, `approved-changes.md`, `handoff-failure.md`) live at **iteration root** (`iteration-<n>/`), NOT inside `<issue-folder>`.

**Failure path**: If task-solver session fails to produce required artifacts (planning loops, agents stall, errors, or no `<issue-folder>` created), record failure in `iteration-<n>/handoff-failure.md` and treat that as iteration's data — diagnose failure as instruction gap (e.g., "devbot doesn't know how to recover when critic returns no feedback"). Do not retry task in same iteration. Failed iterations kept (not deleted) and counted as data points; mark them in tracker with `status: failed`.

### Step 2: Gather Comparison Inputs

Back in main session:

1. **Solver artifacts** — locate `<issue-folder>` (single match for `iteration-<n>/.agents/memory/work/active/*/`) and confirm every required file from Step 1.5 exists inside it (used by Steps 3 and 4).
2. **Reference standards** — architecture rules, `plan` skill, `make-plan` skill (used by Steps 3 and 4).
3. **Previous iteration data** — `iterations_quality.md`, prior `quality-report.md` and `root-cause-analysis.md` (used by Steps 5 and 6 for delta and regression analysis; skip for iteration 1).
4. **Rejected proposals log** — `storage/self-improvement/improve-planning/rejected-proposals.md` (used by Step 7 to suppress re-proposals).

### Step 3: Produce Quality Report

Write `iteration-<n>/quality-report.md` following Plan Quality Report Guide below. Grades **absolute** — measured against reference standards (architecture rules, `plan` and `make-plan` skills, coding standards), not relative to any prior iteration.

Grader is **main-session devbot agent**. Read plan artifacts, reference standards, this skill's grading rubric, and example report at `src/instructions/skills/self-improvement/improve-planning/references/report-example.md` (used as _format_ reference only, not scoring anchor).

#### Solver-execution metrics

In addition to rubric scores, extract following objective metrics from `interactions.md` and record in quality report's Section 0 (Metrics):

| Metric                    | Source                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------ |
| Planning duration         | Wall-clock time between first agent invocation and final plan handoff                                  |
| Agent invocations (total) | Count of all subagent calls during planning                                                            |
| Stall count               | Times workflow had to be unblocked or restarted                                                        |
| [NEEDS_INPUT] signals     | Times solver agent asked human stakeholder question (should be 0 in this kata since approvals skipped) |
| Critic rounds             | Number of architect↔critic exchanges before plan went FINAL                                            |
| Required-artifact gaps    | Missing files from required-artifacts list (Step 1.5)                                                  |

These metrics feed "Solver execution" rubric dimension (see below).

#### Report validation

Before saving, verify report:

- Has all 7 sections with correct numbering (0 Metrics, 1 Positives, 2 Negatives, 3 Regressions, 4 Things to Improve, 5 Instructions to Change, 6 Grade, 7 Grade Justification)
- Every Negative has Problem / Impact / Fix
- Grade table dimension weights sum to 100%
- Weighted total math correct

If report fails validation, fix before proceeding to Step 4. Do not produce RCA against malformed report.

### Step 4: Root-Cause Analysis

Write `iteration-<n>/root-cause-analysis.md`. For each weakness in the quality report, produce a structured RCA block:

```markdown
### RCA-<n>: <Weakness title from quality report>

| Field                    | Value                                                                                                                                                                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Quality report ref**   | Section 2.X                                                                                                                                                                                                                                                                     |
| **Dimensions affected**  | One or more of the rubric dimensions                                                                                                                                                                                                                                            |
| **Responsible agent**    | Which agent should have caught/prevented this (must be devbot/po/architect/critic)                                                                                                                                                                                              |
| **Instruction file**     | Exact path to the file with the gap                                                                                                                                                                                                                                             |
| **Gap type**             | Missing rule / Ambiguous rule / Contradictory rule / Rule in wrong location                                                                                                                                                                                                     |
| **Current text**         | Quote the relevant section (or "absent")                                                                                                                                                                                                                                        |
| **Required text**        | What the instruction should say                                                                                                                                                                                                                                                 |
| **Consistency check**    | List any other files/skills that already cover this topic. Confirm the required text does NOT contradict them; if it would, the fix must update those files too.                                                                                                                |
| **Regression risk**      | Could fixing this break something else? What?                                                                                                                                                                                                                                   |
| **Previously rejected?** | Search `rejected-proposals.md` by **target file + section** (not by exact text). If a prior rejection covers the same file+section AND the rejection reason still applies, mark "skip" and explain. Otherwise mark "no" or "supersedes prior rejection because <new evidence>". |
```

A single weakness may affect multiple rubric dimensions — list all in "Dimensions affected".

### Step 5: Regression and Effectiveness Check

**Skip for iteration 1** (no prior iteration to compare).

Compare this iteration against previous:

- **Regression**: Previous positive (1.X) is now negative. Identify which approved change in iteration `<n-1>` likely caused it.
- **Ineffective fix**: Previous negative persists despite approved change targeting it. Change didn't work.
- **Effective fix**: Previous negative gone. Note which approved change caused it — builds evidence about what kinds of edits work.

**Comparison validity**: skip entire step (and tag iteration accordingly) if any of following changed since previous iteration:

- Model (`metadata.json.model`)
- Rubric version (`metadata.json.rubric_version`)
- Kata under `references/poke-api-kata/` (any change invalidates entire history — restart from iteration 1)

Add `## Regressions and Fix Effectiveness` section to quality report. If skipped, record reason in that section ("comparison invalidated by model change", etc.).

### Step 6: Update Iterations Tracker

**Skip delta column for iteration 1** (no prior to subtract from). All other columns apply.

Tracker file `storage/self-improvement/improve-planning/iterations_quality.md` has TWO sections — both MUST be updated in same step. Skipping either part leaves iteration in [PARTIAL] state.

#### Part A — Append row to summary table at top

Use this exact header (initialise file with this header if it doesn't exist). Table records each rubric dimension's raw score (0–100) so per-dimension trends visible without opening every quality report. Immediately under header row, file MUST keep `Weights` reference row showing current rubric weights (this row is data, not comment, so per-dim columns meaningful at glance):

```markdown
| Iter | Status  | Model | Rubric | Spec | Plan | Arch | Clar | Proc | Def | Solv | Grade | Δ Grade | Issues addressed | Issues remaining | Regressions | Effective fixes | Stalls | Critic rounds |
| ---- | ------- | ----- | ------ | ---- | ---- | ---- | ---- | ---- | --- | ---- | ----- | ------- | ---------------- | ---------------- | ----------- | --------------- | ------ | ------------- |
| —    | weights | —     | v3     | 35%  | 21%  | 21%  | 10%  | 5%   | 5%  | 3%   | 100%  | —       | —                | —                | —           | —               | —      | —             |
```

- Status: `success` | `failed` | `model-change` | `rubric-change`
- Model and Rubric flagged with ⚠️ if changed from prior iteration
- Spec / Plan / Arch / Clar / Proc / Def / Solv: raw 0–100 score for each rubric dimension (same numbers as per-iteration quality report's Grade table, before weighting)
- Grade: weighted total, rounded to nearest integer
- Δ Grade: blank for iteration 1 and for iterations following any flagged change
- When rubric version changes, append new `weights` reference row with updated weights immediately below previous one and tag iteration row `rubric-change`

New row goes immediately after previous iteration's row (preserving Iter ascending order), BEFORE `---` separator introducing per-iteration sections.

#### Part B — Append per-iteration narrative section below table

Under new `## Iteration <n>` heading at bottom of file (after last existing `## Iteration <n-1>` section), include:

- Grade
- Reflection (link to `interactions.md`, RCA, quality report, and all artefacts produced in `iteration-<n>/`)
- Issues addressed (with [PARTIAL] / HELD / CONFIRMED markers)
- Issues remaining (numbered N<n>.<i>, with severity)
- Regressions and root-cause-of-regression
- Effective fixes (mechanism land rate)
- Stalls and critic rounds
- Hypothesis for next iteration
- Lessons about which kinds of instruction edits work (cite relevant files from `latent/global/` or `latent/learnings/` if applicable)

#### Verification gate (MUST run before declaring Step 6 complete)

After writing both parts, run these two checks:

1. `grep -c "^| ${n} " storage/self-improvement/improve-planning/iterations_quality.md` — MUST return `1` (exactly one table row for current iteration).
2. `grep -c "^## Iteration ${n}$" storage/self-improvement/improve-planning/iterations_quality.md` — MUST return `1` (exactly one narrative section).

If either check returns `0`, part missing — write before continuing. If either returns `>1`, duplicate exists — remove before continuing. Step 6 NOT complete until both checks return `1`.

### Step 7: Propose Instruction Improvements

Write `iteration-<n>/proposals.md`. For each proposal:

- **File**: exact path (must be one of: `src/instructions/agents/{devbot,po,architect,critic}.md`, `src/instructions/skills/workflow/plan/SKILL.md`, `src/instructions/skills/workflow/make-plan/SKILL.md`, `src/instructions/skills/workflow/review-plan/SKILL.md`)
- **Location**: section name or line reference
- **Before**: quote current text (or "absent")
- **After**: proposed text
- **Rationale**: which weakness this prevents and why
- **Regression risk**: what could go wrong
- **Linked RCA**: `RCA-<n>`

**Skip** any proposal whose RCA's "Previously rejected?" check returned "skip".

#### Presenting proposals to user

1. **Coverage**: every finding from iteration's evaluation (every negative N<n>.<i> in `quality-report.md`, every RCA item, every regression) MUST produce corresponding proposal in `proposals.md`. No cap on total proposals. Evaluator does not select subset by "expected lift" or "highest impact" — every finding addressed in iteration that surfaced it. Silently dropping low-impact findings was prior behaviour (capped at 3-5); now forbidden because dropped findings recur indefinitely without audit trail and inflate next iteration's defect count.
2. **Ordering**: order proposals in `proposals.md` by descending expected impact (rubric-point gain × confidence). Shapes user's reading order but does NOT filter set — low-impact items appear at bottom but still present and still require decision.
3. **Single batch**: present all proposals to user in single batch. Do not paginate, summarise, or omit. User may need to scroll; acceptable. Multi-batch presentation is failure mode this rule prevents — once proposal moves to "batch 2" there is pressure to drop it.
4. **Per-proposal decision**: each proposal gets one of `approved`, `rejected (<reason>)`, or `modified (<new text>)`.
5. **Override shortcuts**: user may say "approve all", "reject all", or "approve all except <list>". Shortcuts apply across full set, not just visible subset.

No `defer` option. Every proposal must resolve to approved/rejected/modified in iteration that produced it. Undecided proposals at end-of-batch treated as rejected (with reason "no decision before batch close").

##### Verification gate (MUST run before presenting proposals)

Before presenting `proposals.md` to user, verify coverage:

1. Count negatives in `quality-report.md`: `grep -c "^### N${n}\." iteration-${n}/quality-report.md` — call this `F` (findings).
2. Count proposals in `proposals.md`: `grep -c "^### P[0-9]" iteration-${n}/proposals.md` — call this `P`.
3. `P` MUST be `>= F`. If `P < F`, at least one finding has no proposal — return to Step 7 and write missing proposals before presenting.

A proposal may address multiple findings (record all linked findings under "Linked RCA"); finding may produce multiple proposals (split when single fix would change too much at once). `P >= F` gate ensures coverage; does not require strict 1:1 mapping.

Record decisions in two places:

- **Approved** → write row in `iteration-<n>/approved-changes.md` (see Step 7.5 sub-step 1 below — this file MUST be created before any edits applied).
- **Rejected** → append to `storage/self-improvement/improve-planning/rejected-proposals.md` with target file, target section, full text, user's reason, iteration number. Future iterations match by **file + section** (not exact text), see RCA "Previously rejected?" check.
- **Modified** → record modified text in `approved-changes.md`. Also log in `rejected-proposals.md` referencing original (file + section + "modified — see iteration N approved-changes.md").

#### Apply and commit (end of Step 7)

After all decisions captured, orchestrator MUST execute sequence in order. **Each numbered step mandatory and non-skippable.** Skipping `approved-changes.md` write step (sub-step 1 below) is iter-5 audit-trail defect this sequence designed to prevent.

1. **Write `iteration-<n>/approved-changes.md` BEFORE touching any source file.** Use format established by prior iterations (header, "Applied edits" table with `# / File / Change / Verified` columns, "Modifications from proposed text" section, "Hypothesis carried into iter-<n+1>" section, "Next" section, and "Applied" footer block left empty for now). File is source of truth for _what was approved_; commit is source of truth for _that it was applied_. Both must exist independently. If you find yourself about to apply edits without this file written, stop and write it first.
2. **Audit cross-cutting impact** — when approved change renames file or symbol referenced elsewhere (e.g., changing `PLAN.md` to `PLAN-ARCH-*.md`), grep entire `src/` tree for stale references and update them in same edit pass. Consistency across codebase is hard requirement; "scope of edits" table is suggestion for _where defects originate_, not fence around _where fixes go_.
3. **Apply edits** in order recorded in `approved-changes.md` (foundational rules first; rules depending on them after; renames last because widest blast radius).
4. **Verify working tree** — `git status` should show `approved-changes.md` plus files touched by approved edits, and nothing else. If anything unexpected appears, abort commit and resolve before continuing.
5. **Single commit** — stage exactly files touched by approved edits AND `approved-changes.md`, then commit with message:
    ```
    chore(planning): apply iteration-<n> approved planning improvements

    <one-line summary per approved change, referencing iteration-<n>/approved-changes.md>
    ```
    Do NOT amend previous commit. Do NOT push. User pushes when they choose.
6. **Append "Applied" footer to `approved-changes.md`** with commit SHA and list of files actually touched (may exceed proposals' enumerated targets due to cross-cutting audit in step 2). Then make second tiny commit `chore(planning): record iteration-<n> applied footer`, OR amend previous commit ONLY IF nothing pushed and previous commit is one just made in sub-step 5. "Applied" footer is what Step 0 of next iteration verifies; without it, next iteration's Step 0 gate halts.

### Step 8: Decide Whether to Continue

Evaluate stopping criteria and report decision:

| Condition                                       | Action                                                                                      |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Grade ≥ 95                                      | Suggest stopping — diminishing returns likely                                               |
| Grade delta < 2 for two consecutive iterations  | Suggest stopping — plateau reached                                                          |
| User says "done" or "stop"                      | Stop                                                                                        |
| Regressions > effective fixes in this iteration | Pause — recommend reverting last changes; ask user to confirm before next iteration         |
| Model changed mid-loop                          | Tag iteration `model-change`; do not compute delta; warn user the comparison is invalidated |
| Rubric version changed                          | Same as model change — tag, no delta, warn                                                  |
| Kata changed                                    | Stop the loop. Restart from iteration 1                                                     |
| Otherwise                                       | Schedule next iteration — user starts a new task-solver session and the loop continues      |

### Step 9: Periodic Reviews (every 5 iterations)

Every 5 iterations, main session prompts user with two reviews:

**Rubric review**: "Review rubric? Look for: dimensions where every iteration scores same (non-discriminating), dimensions whose weights no longer match what we care about, missing dimensions for failure modes we keep hitting."

Update rubric only with explicit user approval. When changed:

1. Bump `rubric_version` value in this file (e.g., `v1` → `v2`) and rewrite rubric.
2. All future iterations record new `rubric_version` in `metadata.json`.
3. Subsequent iterations cannot compute deltas against pre-change iterations (handled by Step 5's validity rules).

**Lessons consolidation**: Read per-iteration narratives from `iterations_quality.md` (last 5 iterations). Extract recurring patterns about which kinds of instruction edits work and which don't. Append dated entry to `storage/self-improvement/improve-planning/lessons.md` with consolidated findings. Prevents lessons from being lost in scattered narratives.

---

## Plan Quality Report Guide

Use this guide to produce comparable quality reports for implementation plans.

**Rubric version**: `v3`

### Report Structure

Every report MUST use this exact structure:

```markdown
# Quality Report: <plan-name> (Iteration <N>)

## Purpose

<1–3 sentences: what the plan is for, which LLM(s) it targets, any known execution results>

---

## 0. Metrics

<Solver-execution metrics extracted from interactions.md — see Step 3 table>

## 1. Positives

<Numbered subsections (1.1, 1.2, ...) — one per strong point>

## 2. Negatives

<Numbered subsections (2.1, 2.2, ...) — one per weak point, each with Problem/Impact/Fix>

## 3. Regressions and Fix Effectiveness

<Comparison vs previous iteration — regressions, ineffective fixes, effective fixes. Omit section for iteration 1 or when comparison is invalidated; in the latter case state the reason here.>

## 4. Things to Improve

<Prioritized list of changes that would raise the grade>

## 5. Instructions to Change

<Concrete edits to specific files, with before/after or proposed additions>

## 6. Grade

<Dimension table + weighted total>

## 7. Grade Justification

<"Why not higher" + "Why not lower" — connects deductions to specific evidence>
```

### Evaluation Dimensions

Score each dimension 0–100, then compute weighted total.

| Dimension                           | Weight | What to evaluate                                                                                                                                                                                                                                   |
| ----------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Specificity & completeness**      | 35%    | Does every task have testable ACs? Are file paths, class names, field types, behaviors explicit? Would lower-reasoning LLM need to guess anything?                                                                                                 |
| **`plan` compliance**               | 21%    | Does plan satisfy every rule in `plan` and `make-plan` skills? Check each bullet point with line references.                                                                                                                                       |
| **Architecture correctness**        | 21%    | Does plan match architecture rules? Directory structure, dependency rules, naming conventions. Is there architect review confirming this?                                                                                                          |
| **Clarity for lower-reasoning LLM** | 10%    | Are rules centralized or scattered? Are implicit assumptions made? Would model with limited context window find all necessary information within task it's working on?                                                                             |
| **Process guidance**                | 5%     | Does plan address: reviewer frequency, commit strategy, stall recovery, delegation batch size, error escalation?                                                                                                                                   |
| **Defensive completeness**          | 5%     | Does plan account for all coding-standard rules? Are edge cases and known pitfalls addressed?                                                                                                                                                      |
| **Solver execution**                | 3%     | Objective metrics from Section 0: low stall count, low critic rounds, no [NEEDS_INPUT], no required-artifact gaps. Score 100 if all metrics at best; deduct for stalls, missing artifacts, excessive critic rounds (>3), any [NEEDS_INPUT] signal. |

Weights sum to 100%.

**v3 rationale**: weights rebalanced from v2 (25/15/15/20/10/10/5) by halving bottom four dimensions and redistributing freed 20 percentage points proportionally to top three (Specificity, `plan` compliance, Architecture correctness). Rationale: bottom four dimensions either non-discriminating across iterations (Architecture, Defensive — most plans clear them) or weighted disproportionately to their information value (Clarity, Process). Concentrating weight on top three sharpens signal on dimensions where iterations actually move.

### Computing the Final Grade

```
Grade = Σ (dimension_weight × dimension_score)
```

Round to the nearest integer.

### Writing Negatives

For each negative, use this format:

```markdown
### 2.N <Title> (-X points)

**Problem:** <What rule or standard violated or missing. Reference source document.>

**Impact:** <What failure this caused or could cause in implementation.>

**Fix:** <Concrete change to plan that would resolve this.>
```

Point deductions relative to dimension they affect:

- Missing rule affecting ALL tasks: -2 to -4 points
- Missing rule affecting ONE task: -0.5 to -1 point
- Ambiguity that could be misinterpreted: -1 to -2 points
- Process gap with proven impact: -2 to -3 points

### Scoring Guidelines — What 100 Looks Like

| Dimension                       | 100/100 means                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Specificity & completeness      | Every class, method, field, behavior, file path named. Zero ambiguity. Edge cases enumerated.          |
| `plan` / `make-plan` compliance | Every rule in both skills satisfied with traceable evidence.                                           |
| Architecture correctness        | Architect review confirms compliance. Directory tree matches architecture exactly.                     |
| Clarity for lower-reasoning LLM | All rules centralized. Each task's AC self-contained. No implicit knowledge required.                  |
| Process guidance                | Reviewer mandate, commit strategy, stall recovery, delegation limits, error escalation — all explicit. |
| Defensive completeness          | Every coding-standard rule reflected. Known pitfalls addressed. All edge cases have test criteria.     |
| Solver execution                | Zero stalls, zero [NEEDS_INPUT], ≤3 critic rounds, all required artifacts present.                     |

### Comparability Rules

1. Always use same 7 dimensions with same weights (until rubric review in Step 9 changes them, in which case bump rubric version)
2. Always use same point-deduction scale
3. Always reference same standard documents
4. Always end with single integer grade
5. Never grade on effort or length
6. Grade plan as written, not as intended — if rule implied but not stated, it's gap

---

## Storage Layout

```
storage/self-improvement/improve-planning/
├── iterations_quality.md           # Cross-iteration tracker
├── rejected-proposals.md           # User-rejected proposals (don't re-propose; matched by file+section)
├── lessons.md                      # Consolidated learnings (updated every 5 iterations)
└── iteration-<n>/
    ├── metadata.json               # Main session: iteration, timestamp, model, rubric_version
    ├── handoff-failure.md          # Main session: only if task-solver failed
    ├── quality-report.md           # Main session output
    ├── root-cause-analysis.md      # Main session output
    ├── proposals.md                # Main session output
    ├── approved-changes.md         # Main session: user-approved subset (applied & committed at end of Step 7)
    └── .agents/memory/work/active/<YYYYMMDD-HHMMSS-NN>-<slug>/  # Solver issue-folder
        ├── backlog.md              # Solver output
        ├── PLAN-ARCH-*.md          # Solver output (combined architecture spec + implementation plan)
        ├── PLAN-REVIEW-*.md        # Solver output (critic review)
        ├── summary.md              # Solver output (planning summary)
        └── interactions.md         # Solver output (from template)
```

**Retention**: failed iterations (with `handoff-failure.md`) kept indefinitely as data points. _Never_ auto-deleted. To free space, archive under `storage/self-improvement/improve-planning/archive/iteration-<n>/` manually.

---

## Checklist Before Submitting an Iteration

This checklist is **mandatory gate**. Before declaring iteration N complete and moving to Step 8, verify every item. If any item fails, fix before proceeding. Record completion as final entry in iteration's quality report (single line: `Checklist: passed at <ISO 8601>`).

- [ ] Iteration number determined (max existing + 1)
- [ ] Approved changes from previous iteration applied (or recovery path executed)
- [ ] Setup script ran cleanly (or rolled-back partial folder before retry)
- [ ] `metadata.json` records iteration, timestamp, model, rubric version
- [ ] User warned if model or rubric version changed
- [ ] Task-solver session ran in isolation
- [ ] Solver `<issue-folder>` located (single match for `iteration-<n>/.agents/memory/work/active/*/`)
- [ ] All required solver artifacts present in `<issue-folder>` (`backlog.md`, `PLAN-ARCH-*.md`, `PLAN-REVIEW-*.md`, `summary.md`, `interactions.md`)
- [ ] Quality report has all 8 sections (0–7) with correct numbering
- [ ] Section 0 (Metrics) populated from `interactions.md`
- [ ] Every negative has Problem/Impact/Fix
- [ ] Grade table sums to 100% weights
- [ ] Weighted total math is correct
- [ ] Report passed validation (Step 3 sub-step) before RCA was started
- [ ] Root-cause analysis written, one structured RCA per weakness
- [ ] RCA "Responsible agent" is one of devbot/po/architect/critic
- [ ] RCA "Dimensions affected" lists all rubric dimensions impacted by the weakness
- [ ] RCA "Consistency check" performed for every proposed required text
- [ ] RCA "Previously rejected?" matched by file+section, not exact text
- [ ] Regression and effectiveness check performed (skipped only for iteration 1 or invalidated comparisons; reason recorded)
- [ ] Iterations tracker updated; delta blank for iteration 1 and for iterations following any flagged change
- [ ] Proposals only target in-scope files (devbot/po/architect/critic agents + plan/make-plan/review-plan skills)
- [ ] Proposals exclude items previously rejected (per `rejected-proposals.md` file+section match)
- [ ] Each proposal has before/after, rationale, regression risk, linked RCA
- [ ] Proposals presented in batches of ≤5
- [ ] User decisions recorded: approved → `approved-changes.md`, rejected → `rejected-proposals.md`
- [ ] `iteration-<n>/approved-changes.md` was written **before** any source-file edits were applied (Step 7.5 sub-step 1 — non-skippable)
- [ ] `iteration-<n>/approved-changes.md` has an "Applied" footer with commit SHA and the full list of files touched (Step 7.5 sub-step 6)
- [ ] Stopping criteria evaluated and reported
- [ ] If iteration is multiple-of-5: rubric review prompt offered AND lessons consolidated into `lessons.md`
