# DevBot Agent Modus Operandi — Sketch

**Compiled**: 2026-07-31 | **Keywords**: devbot, modus-operandi, multi-agent, orchestration, workflow, lifecycle

---

## 1. Two Operating Modes

DevBot is not one agent — it's **one agent definition that can run in two distinct modes**, selected by the agent file loaded:

| Mode                | Agent      | File                                     | Role                                                                                                   |
| ------------------- | ---------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **Pair programmer** | `DevBot`   | `src/agentic/devbot/agents/devbot.md`    | Sits alongside human, thinks together, writes together incrementally. Never autonomous.                |
| **Orchestrator**    | `TeamLead` | `src/agentic/devteam/agents/teamlead.md` | Single entry point. Classifies work, routes to specialists, leads planning + implementation workflows. |

**Key distinction**: DevBot writes code (with human). TeamLead NEVER writes code — delegates ALL code to `@developer`, ALL tests to `@tester`.

The same agentic infrastructure powers both. Which mode runs depends on which `.md` agent file is loaded as the primary agent.

---

## 2. Agent Roster (8 Subagents + Orchestrator)

```
                        ┌──────────────┐
                        │  TeamLead     │  ← orchestrator / entry point
                        │  (DevBot in   │
                        │  orchestration│
                        │  mode)        │
                        └──────┬───────┘
                               │ classifies & routes
          ┌────────────────────┼────────────────────────┐
          │                    │                        │
    ┌─────▼─────┐       ┌─────▼─────┐           ┌──────▼──────┐
    │   Scout   │       │    PO     │           │  Architect  │
    │  (context │       │ (product  │           │  (designs   │
    │  gatherer)│       │  owner)   │           │   plans &   │
    └───────────┘       └───────────┘           │   ADRs)     │
                                                 └──────┬──────┘
    ┌───────────┐       ┌───────────┐           ┌──────▼──────┐
    │  Critic   │       │ Reviewer  │           │  Developer  │
    │  (plans & │       │ (code     │           │  (writes    │
    │  codebase │       │  review)  │           │   all code) │
    │  audits)  │       └───────────┘           └─────────────┘
    └───────────┘
    ┌───────────┐       ┌───────────┐
    │  Tester   │       │ Security  │
    │  (writes  │       │ (audits,  │
    │  & runs   │       │  threat   │
    │  tests)   │       │  models)  │
    └───────────┘       └───────────┘
```

| Agent         | Mode     | Can write code? | Core responsibility                                      |
| ------------- | -------- | --------------- | -------------------------------------------------------- |
| **TeamLead**  | Primary  | ❌ Never        | Classify, route, orchestrate planning + implementation   |
| **Scout**     | Subagent | ❌ Never        | Gather context, produce `thinking/` reports              |
| **PO**        | Subagent | ❌ Never        | Backlog creation, requirements, product semantics        |
| **Architect** | Subagent | ❌ Never        | Technical plans, ADRs, design decisions                  |
| **Critic**    | Subagent | ❌ Never        | Review plans, audit codebase for drift                   |
| **Developer** | Subagent | ✅ Only one     | Implement plans into production code                     |
| **Reviewer**  | Subagent | ❌ Never        | Review changesets against plan + conventions             |
| **Tester**    | Subagent | ✅ Tests only   | Write tests before code, validate after                  |
| **Security**  | Subagent | ❌ Never        | Security audits, threat models, vulnerability assessment |

Roles are **strictly enforced** via agent instructions (MUST/MUST NOT rules). Auditor agents (Security, Critic) have `edit: deny` in their permissions.

---

## 3. Communication Protocol (`devbot:agent-communication`)

All agents use a structured protocol with **terminal status markers**:

| Marker          | Meaning                                      |
| --------------- | -------------------------------------------- |
| `[FINISHED]`    | Work genuinely complete                      |
| `[BLOCKED]`     | Cannot proceed, external action needed       |
| `[NEEDS_INPUT]` | Needs clarification from human/another agent |
| `[PARTIAL]`     | Work incomplete, must resume                 |

**Critical rules**:

- Every assistant message must end with exactly one marker on its own line.
- Orchestrator verifies subagent deliverables actually exist on disk before accepting `[FINISHED]` (post-delegation verification).
- **Prompt-opener gate**: For file-producing subagents (Architect, Critic, PO), first sentence of delegation prompt MUST be imperative `Write <canonical-path> ...`. Agents `[BLOCKED]` immediately if gate fails.
- **First-tool-call invariant**: Once gate passes, first tool call must be the declared `write`/`edit` — no reads first.
- **Stall ceiling**: Same subagent returning `[PARTIAL]` twice → escalate to human, don't do the work yourself.

---

## 4. Development Lifecycle (6 Stages)

DevBot guides human through these stages, auto-detecting from conversation cues:

```
DEFINE ───► PLAN ───► BUILD ───► VERIFY ───► REVIEW ───► SHIP
```

| Stage      | What happens                                                   | Key skills                                               |
| ---------- | -------------------------------------------------------------- | -------------------------------------------------------- |
| **DEFINE** | Clarify requirements, constraints, edge cases                  | `spec-driven-development`, `idea-refine`, `interview-me` |
| **PLAN**   | Break work into ordered tasks, create todo list, user sign-off | `planning-and-task-breakdown`, `devbot:make-plan`               |
| **BUILD**  | Execute tasks one at a time; load tech context skills          | `incremental-implementation`, `test-driven-development`  |
| **VERIFY** | Debug, investigate failures, confirm spec compliance           | `debugging-and-error-recovery`                           |
| **REVIEW** | Quality, security, simplification review                       | `code-review-and-quality`, `code-simplification`         |
| **SHIP**   | Pre-launch checks, deployment readiness                        | `shipping-and-launch`                                    |

**Stage gating rules**:

- Never start BUILD until user explicitly opts in ("go ahead", "execute").
- Auto-detect stage from cues ("What should this do?" → DEFINE, "It's not working" → VERIFY).
- Nudge toward next stage when current feels complete, but never block — skipping is allowed with a warning.
- `todowrite` tracks progress; exactly one `in_progress` at a time.

---

## 5. Planning Workflow (`devbot:make-plan` → `devbot:make-plan` SKILL)

**Trigger**: User provides story, epic, or feature request. TeamLead activates.

### Step-by-step:

1. **Classify** the brief as Epic (explicit story list), Story (single non-trivial brief), or Trivial (<3 tasks, clear scope → skip planning, go straight to implement).

2. **PO creates backlog** — `@po` produces `backlog.md` with tasks + acceptance criteria.

3. **Architect designs plan** — `@architect` folds technical implementation plan INTO the same `backlog.md` (no separate PLAN-ARCH document). Uses a **technical-action scope-assignment ladder**: task-level → story-level → epic-level.

4. **Critic reviews plan** — `@critic` checks for correctness, completeness, architectural consistency. Findings classified as BLOCKER, WEAKNESS, WARNING, MINOR, SUGGESTION.

5. **Iterate**: Architect addresses BLOCKERs → Critic re-reviews → repeat until APPROVED.

6. **FINAL-promotion gate**: Orchestrator marks plan FINAL only after critic round with APPROVED verdict AND all findings resolved/dispensed. Plan reaches FINAL status only when `planning-complete.md` written with all artifact verifications.

7. **Human approves** → transition to Implementation Stage.

### Artifact folder structure:

```
.agents/memory/work/active/YYYYMMDD-HHMMSS-NN-<slug>/
  backlog.md                     # Combined: tasks + ACs + technical actions
  PLAN-REVIEW-YYYY-MM-DD-NNN.md  # Critic review
  summary.md                     # Planning summary for human
  planning-complete.md           # Gate: lists all required artifacts as [x]
```

**Epic path** extends this with sub-folders per story, each with its own combined `backlog.md`.

---

## 6. Implementation Workflow (`devbot:implement-story` SKILL)

**Trigger**: Plan at FINAL status, human approved. TeamLead activates.

### Per-task cycle (sequential by default):

```
Tester ──► Developer ──► Reviewer ──► Address Findings ──► Mark Done
```

1. **Tester** — writes tests for each acceptance criterion BEFORE developer touches code (TDD pattern). Saves test files, reports `[FINISHED]`.

2. **Developer** — implements following plan's technical actions. MUST:
    - Make tests pass
    - Run full test suite before commit
    - Commit with specific `git add <files>` (never `git add -A`)
    - Verify each written file exists with `ls -la` before signalling `[FINISHED]`
    - Signal with commit summary (e.g. "Committed: feat(auth): add JWT handler")

3. **Reviewer** — reviews changeset against plan + conventions. Produces review report. Gate: required if 2+ files changed (excluding fixtures/config/docs).

4. **Address findings** — developer fixes review issues, commits, iterates until no remaining issues.

5. **Mark done** — strikethrough task in `backlog.md`, progress report to human.

6. **Capture lessons** → move to next task.

### Parallelization allowed when:

- No shared files, no dependencies, no shared state, self-contained tests.
- Otherwise strictly sequential — especially DB migrations.

### Completion:

- Verify no test regression
- Run retrospective (`devbot:make-retrospective`)
- Archive work folder to `work/archive/`

---

## 7. Operational Patterns & Guardrails

### Context gathering (ongoing)

- **Session start**: DevBot runs `devbot:gather-context` skill. TeamLead delegates to `@scout` with explicit keywords.
- **Every user interaction**: Pause and evaluate if new keywords emerged → search memory or re-gather before responding.

### Delegation rules (TeamLead)

- File-producing prompts MUST open with `Write <canonical-path> <verb>...`
- Pre-send self-check: re-read first sentence, verify imperative form, log in `interactions.md`.
- Audit-log honesty: every claim about a subagent deliverable must cite either artefact path + verifying observation, or exact tool call output observed.
- **Never** do subagent's work yourself (stall ceiling: escalate after 2 `[PARTIAL]`s).

### Code quality gates (Developer)

- List assumptions before starting, wait for confirmation.
- Run `make test` (full suite) before every commit.
- Verify Python files parse (`python3 -m py_compile <file>`) before commit.
- Commit after every completed task — task not finished until committed.
- File-existence verification: `ls -la` every claimed file before `[FINISHED]`.
- Simplify: "Can this be done in fewer lines?"
- **Pre-existing issues**: Any pre-existing issue identified while executing a task MUST be clearly explained and explicitly proposed for follow-up work at the end of the task. The codebase must always be in perfect shape, as far as we know.

### Architect/Critic gates

- **Prompt-opener gate**: Block immediately if first sentence lacks `Write/Update <path>`.
- **First-tool-call invariant**: First call must be the declared write — no reads before.
- **Critic discriminating-bar checklist**: Enumerate every verbatim block in plan, verify each has justifying annotation.
- **Critic-finding routing**: BLOCKERs → re-delegate to architect. SUGGESTIONs on single step → orchestrator may self-fix. WEAKNESS single-line → orchestrator may self-fix with architect re-verification.

### Memory & learning

- `devbot:remember-session` captures session state on wrap-up / idle.
- `devbot:search-memory` and `search-memories` tools for recalling past learnings.
- PDRs (Product Decision Records) and ADRs (Architecture Decision Records) in `.agents/memory/latent/`.
- `thinking/` for scratch files — promote useful findings to `latent/` before session close.

---

## Summary

DevBot's modus operandi is a **disciplined, gates-heavy multi-agent system** with two faces:

- **DevBot mode** (pair programmer): Human driver, incremental work, think-together ethos. No autonomy.
- **TeamLead mode** (orchestrator): Classifies every request, routes to the right specialist, leads planning (PO → Architect → Critic → approve) and implementation (Tester → Developer → Reviewer cycles), but NEVER writes code or tests itself.

The system enforces quality through structural constraints: prompt-opener gates, first-tool-call invariants, post-delegation file-existence verification, stall ceilings, FINAL-promotion gates, and audit-log honesty. Every agent has narrow, well-defined scope with strict MUST/MUST NOT rules. The lifecycle is stage-gated (DEFINE → PLAN → BUILD → VERIFY → REVIEW → SHIP) with auto-detection from natural conversation cues.
