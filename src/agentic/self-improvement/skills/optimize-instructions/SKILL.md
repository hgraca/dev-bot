---
name: optimize-instructions
description: "Optimizes agent instruction files for clarity, token efficiency, and pattern compliance. Use this skill whenever creating, reviewing, or rewriting role files, skill files, workflow files, or context files for a multi-agent system."
---

# Skill: Instructions Optimization

Structured procedure for reviewing and improving agent instruction files. Ensures files minimal, precise, non-redundant, aligned with agentic design patterns.

## When to Apply

- When creating a new role, skill, workflow, or context file
- When reviewing an existing instruction file for quality
- When rewriting instructions to reduce token usage
- When consolidating or deduplicating across multiple instruction files
- When onboarding a new agent role into the system

## Procedure

### Step 1: Classify the file

Determine the file type. Each type has a required structure (see File Structure below).

| Type     | Purpose                                           | Key constraint                           |
| -------- | ------------------------------------------------- | ---------------------------------------- |
| Role     | Who the agent is, what it may/must/must not do    | No procedures — reference skills instead |
| Skill    | How to perform a specific task                    | Self-contained, loaded on demand         |
| Workflow | How agents coordinate across a multi-step process | Orchestrates agents, not procedures      |
| Context  | Facts and rules always loaded at session start    | Short, high-signal, global               |

### Step 2: Apply writing rules

Check every rule against this checklist. For each violation, rewrite rule.

1. **Economy** — Does this rule change outcomes? Testable? Remove if not. Remove qualifiers ("generally", "usually", "try to"). Every instruction costs tokens.
2. **Precision** — One action or one prohibition? Uses measurable language ("must", "must not", "only")? Auditable?
3. **Positive phrasing** — States desired action, not what to avoid? No double negatives? Prohibitions reserved for safety/security only?
4. **Non-redundant** — Rule discoverable from file structure or other docs? Duplicates rule in another file? If so, keep one canonical location, reference from others.
5. **Priority ordered** — Rules ordered: safety > correctness > determinism > style?
6. **Scoped** — Global (belongs in context) or task-specific (belongs in skill)? In right file?
7. **Bounded** — Defines defaults for ambiguity? States when to stop and what to report? Requires questions only for destructive/security/credential actions?
8. **Output contract** — Specifies structured completion format: status, reason, validation result, risks?

### Step 3: Check structure compliance

Validate the file against the required structure for its type.

#### Role files

| Section          | Rule                                                  |
| ---------------- | ----------------------------------------------------- |
| Identity         | One sentence: role name + primary responsibility      |
| Skills           | One bullet per skill: trigger condition -> skill name |
| Activation       | Trigger, input, preconditions                         |
| Responsibilities | Verifiable actions, not aspirations                   |
| MUST             | Atomic, measurable, priority-ordered                  |
| MUST NOT         | Each prevents a specific failure mode                 |
| Collaboration    | One format definition (e.g., Q/A/Rationale)           |
| Escalation       | Template: target role, reason, context, impact        |

Role files reference skills. Procedures belong in skills, not roles.

#### Skill files

| Section       | Rule                                           |
| ------------- | ---------------------------------------------- |
| Frontmatter   | YAML: `name`, `description` with trigger words |
| When to Apply | Specific activation criteria                   |
| Procedure     | Numbered steps, each with verifiable output    |
| Templates     | Blockquoted with all required fields           |
| Definitions   | Table/bullets for severity, status, categories |

Skills are loaded on demand. Self-contained — usable without reading the referencing role file.

#### Workflow files

| Section            | Rule                                                              |
| ------------------ | ----------------------------------------------------------------- |
| Goal               | One sentence                                                      |
| Process            | Numbered steps: responsible agent + artifact produced             |
| Rules              | Atomic, testable constraints                                      |
| Exception handling | Reference `exception-handling` skill + workflow-specific recovery |

Workflows orchestrate agents. Agent procedures belong in skills.

### Step 4: Validate pattern coverage

Check whether the file addresses the design patterns relevant to its scope. Not every file needs every pattern — match patterns to file type and purpose.

#### Decomposition & Routing

- Each step: one goal, one verifiable output, one responsible agent
- Structured artifact output (JSON, structured Markdown) between steps
- Validate output before proceeding; fix failed steps, do not skip
- Route to agent whose role covers the task; do not assign outside scope
- Role files must contain activation triggers for unambiguous routing
- One delegation per agent, each in its own session and context
- Fallback route for unrecognized inputs
- Name required tools explicitly; do not constrain when any tool works
- Parallel only when tasks share no files, dependencies, state, or fixtures; default to sequential
- Aggregation after parallel tracks is sequential — reconcile with full validation

#### Context Engineering

- Context quality determines output quality
- Curate per step: only information relevant to the current task
- Engineer handoffs: summarize, extract, discard noise; never pass raw output
- Load one skill per delegation
- Three context layers: system prompts, external data (tools/docs), implicit data (identity/history/environment)

#### Communication & Collaboration

- Division of labor: defined MUST/MUST NOT boundaries per agent, no overlap
- Central coordinator manages workflow; specialists do not coordinate directly
- Artifact-based handoffs with explicit contracts: artifacts, format, expected output
- Every delegation includes: task, context files, deliverable, constraints, acceptance criteria
- Every agent ends with one signal: [FINISHED] | [BLOCKED] | [NEEDS_INPUT] | [PARTIAL]
- Feedback responses: FIXED | DISPUTED | DEFERRED + detail + affected files
- Delegated agents are opaque: define contract, not implementation

#### Reflection & Evaluation

- Separate producer and reviewer; self-review has cognitive bias
- Bound reflection loops: termination condition required (zero BLOCKERs, max N iterations, explicit approval)
- Feedback must cite specific artifacts, paths, or line numbers
- Evaluate trajectories (steps, tool selection, plan adherence), not just output
- Post-task rubric: plan adherence, acceptance criteria, test coverage, code quality
- Retrospective after all tasks: what worked, what to improve, follow-up tasks

#### Planning & Prioritization

- Plan before executing complex work; plans require second-agent review
- Approved plans are contracts; deviations require orchestrator approval
- Final when: zero BLOCKERs, WARNINGs addressed/justified, orchestrator approved
- Fixed workflows for known problems; dynamic planning for discovery
- Three priority levels: goals, sub-tasks, actions
- Re-prioritize dynamically when circumstances change
- Apply defaults when priority/assignment is missing rather than blocking

#### Resilience & Exception Handling

- Detect -> Handle -> Recover (detect: malformed output, API errors, timeouts, stalled session, conflicting instructions, test loop, context overflow, scope creep)
- Bounded retries: 3 failed attempts -> stop and escalate
- Tool failures: retry once, then [BLOCKED]
- Signal when blocked: structured signal with specifics; do not guess outside scope
- Graceful degradation over total failure; skip failed items, log, continue, report
- Signal [PARTIAL] when context degrades; summarize for re-delegation

#### Human Oversight & Guardrails

- Approval gates at defined checkpoints; no self-approved scope changes
- Escalate over assume; wrong assumptions cost more than questions
- No irreversible actions without human approval
- Every role defines how and when to escalate
- MUST/MUST NOT in every role; missing prohibitions are implicit permissions
- Four principles: modularity, observability (structured logging), least privilege, checkpoint/rollback

#### Memory & Learning

- Structured, categorized, scoped memory; not append-only
- Consult before starting; include relevant entries in delegations; stored but unread = zero value
- Prune stale entries; unbounded memory becomes noise
- Three types: semantic (facts), episodic (experiences), procedural (refinable instructions)
- Capture lessons immediately; must be actionable: what, where, trigger
- Self-modifying agents need an overseer

#### Reasoning & Exploration

- Intermediate reasoning steps before final output; creates audit trail
- Self-correct before delivery: find ambiguities, gaps, inaccuracies, then revise
- Allocate more reasoning to harder problems
- In open-ended domains: proactively seek novel information, identify unknowns
- Exploration cycle: generate -> evaluate -> rank -> refine -> repeat

### Step 5: Produce output

Deliver one of:

- **Optimized file** — the rewritten instruction file, ready to use
- **Findings report** — list of violations found, with recommendations

For findings, use this format per finding:

> ### Finding \<n\>: \<Title\>
>
> - **Rule violated**: (writing rule number or pattern name)
> - **Location**: file path and line/section
> - **Problem**: what is wrong
> - **Fix**: concrete rewrite or action

**Auto-clarity override**: Do NOT compress sections that would become ambiguous:

- Security warnings and irreversible action confirmations
- Multi-step sequences where fragment order or omitted conjunctions risk misread
- Any section where compression creates technical ambiguity

## Guiding Principle

Agent output always proposal. Human validates and approves all instruction changes.

---

_Design patterns derived from: Agentic Design Patterns (Gulli, Springer, 2025). 21 patterns, 424 pages._
