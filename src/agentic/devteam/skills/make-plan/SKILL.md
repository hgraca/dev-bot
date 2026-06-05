---
name: make-plan
description: "Plans work of any size AND produces its technical implementation plan inline in the backlog. Detects whether the brief is a list of stories (epic path), a single brief judged trivial (skip planning), or a single brief needing a plan (story path), then folds the architecture/implementation plan into a single combined backlog.md. Use this skill whenever a human stakeholder provides a story, epic, feature request, or business initiative that needs planning before implementation, or whenever a technical implementation plan must be designed across layers — even if they do not say 'plan' explicitly."
---

# Skill: Plan

Plan a body of work AND specify how to build it, in a single combined backlog. Inspect the prompt, route to one of three paths:

| Path        | Trigger                                                                         | Output                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **Epic**    | Prompt contains explicit list of stories, cross-cutting, or multi-step workflow | One epic `backlog.md` (stories + epic-level technical actions) + one combined `backlog.md` per story sub-folder + critic review per story |
| **Trivial** | 1-3 files changed, clear scope, no ambiguity                                    | None. Go straight to `implement-story`                                                                                                    |
| **Story**   | Default for any single non-trivial brief                                        | One combined `backlog.md` (story → tasks, with technical actions at task/story level) + critic review + optional UI/UX                    |

This skill absorbs the former `make-plan` skill. The technical implementation plan is **no longer a separate `PLAN-ARCH-*.md` document** — it is written directly into the backlog. See **Combined backlog format** below for the structure and **Technical-action scope-assignment ladder — MUST** for where each technical action goes.

## When to Apply

- Human stakeholder gives story, epic, feature request, business initiative.
- `/plan` command invoked.
- Planning need before implementation.
- A technical implementation plan must be designed across layers (domain, application, infrastructure, presentation, wiring, migrations, tests). This is done inside the backlog, not as a separate document.

## Artifacts

Place all artifacts in a single `<work-folder>` under `.agents/memory/work/active/`. Planning artifacts not committed to git.

### Folder naming

`.agents/memory/work/active/YYYYMMDD-HHMMSS-NN-<title_slug>/`

`YYYYMMDD-HHMMSS` = current UTC timestamp. `NN` = zero-padded sequential number. Check existing folders, use next available. Timestamp prefix orders chronologically; sequence disambiguates same-second folders.

### Folder structure

**Story path** — all artifacts in `<work-folder>`. The backlog is the combined planning document (tasks, acceptance criteria, AND technical actions). There is NO separate `PLAN-ARCH-*.md`:

```
.agents/memory/work/active/YYYYMMDD-HHMMSS-NN-<story_slug>/
  backlog.md                          # Combined: story → tasks + per-task/story-level technical actions; carries Status
  PLAN-REVIEW-YYYY-MM-DD-NNN.md       # Critic review of backlog.md
  summary.md
  planning-complete.md
  ...
```

**Epic path** — top-level folder holds the epic backlog + summary; each story gets a sub-folder with its own combined backlog:

```
.agents/memory/work/active/YYYYMMDD-HHMMSS-NN-<epic_slug>/
  backlog.md                          # Epic backlog: stories (not tasks) + epic-level technical actions
  summary.md                          # Epic planning summary
  architectural-alignment-YYYY-MM-DD-NN.md   # Phase-1 alignment note (when produced)
  YYYYMMDD-HHMMSS-NN-<story_slug>/    # One per story
    backlog.md                        # Combined: tasks + per-task/story-level technical actions; carries Status
    PLAN-REVIEW-YYYY-MM-DD-NNN.md
    summary.md
    planning-complete.md
    ...
```

**Single combined backlog per unit — MUST**: each planning unit (the epic, and each story) has exactly ONE `backlog.md`. Architecture spec and implementation plan are folded into that file. NEVER emit a separate `ARCH-*.md`, `PLAN-*.md`, or `PLAN-ARCH-*.md` alongside a backlog. If a deviation from the combined-backlog format is unavoidable, document it in an ADR Impact entry.

### One folder per initiative — MUST

Each initiative MUST have exactly one folder. NEVER create a second folder for the same initiative. Story artifacts within an epic go in sub-folders of the epic folder.

### Scratch files

Use `thinking` skill for temp files. Promote useful findings from `thinking/` to latent/ or the issue artifact before session close.

## Combined backlog format

The backlog now carries BOTH the product decomposition (epic → stories → tasks, with acceptance criteria and priorities) AND the technical implementation plan (the layered design previously in `PLAN-ARCH`). The two are interleaved so a reader of any single task sees its goal, acceptance criteria, and the exact technical steps to achieve it.

### Hierarchy

Depending on routing (see Step 1), the backlog takes one of two shapes:

- **Epic path**: `1 epic → n stories → n tasks`. The epic `backlog.md` enumerates stories and carries epic-level technical content; each story sub-folder's `backlog.md` enumerates that story's tasks and carries story-level + per-task technical content.
- **Story path**: `1 story → n tasks`. A single `backlog.md` carries the story header, its tasks, per-task technical content, and story-level technical content.

### Technical-action scope-assignment ladder — MUST

A "technical action" is one concrete unit of implementation work: a file to create or modify, a type/interface to introduce, a wiring change, a migration, a test to add — specified precisely enough that a developer implements it without making design decisions. Each technical action MUST be placed at the **lowest** level of the hierarchy that fully contains its scope:

1. **Task level** — the action implements exactly one task's goal / acceptance criteria. Place it under that task's `#### Technical actions`.
2. **Story level** — the action serves multiple tasks within one story, or is story-wide scaffolding (shared value objects / interfaces consumed across the story's tasks, story-scoped wiring, a story-scoped migration) that maps to no single task. Place it under that story's `### Story-level technical actions`.
3. **Epic level** — the action spans multiple stories, or is cross-cutting / foundation work (shared domain contracts, cross-cutting infrastructure, epic-wide migration ordering, the project-wide technology choice) that maps to no single story. Place it under the epic's `## Epic-level technical actions` in the epic `backlog.md`.

**Default-down rule**: when an action could be argued at two levels, place it at the **lower** (more specific) level and add a one-line cross-reference at the higher level (`See <story>/<task> Technical actions`). This mirrors the planning **Doubt rule**: specificity is cheaper to follow than to reconstruct.

**Story path has two rungs only**: with no epic, the ladder is task → story. Story-level absorbs what would be epic-level; the story header (below) carries the document-level technical content.

### Document-level technical content placement

The former `make-plan` document sections map onto the hierarchy as follows. In the **epic path** "epic-level" means the epic `backlog.md` header; in the **story path** "story-level" means the single `backlog.md` header.

| Former PLAN-ARCH section                  | Merged placement                                                                             |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- |
| Technology Choice (+ Official Doc Review) | Epic header (epic path) / story header (story path) — only if a choice was made              |
| Key Architect Decisions                   | Epic header if cross-cutting; otherwise the story or task it constrains (ladder)             |
| Constraints                               | Epic header (project-wide) / story header (story path)                                       |
| Acceptance Criteria                       | Restated per task; story-wide AC at story level                                              |
| Steps (Layer/Files/Types/Behaviour/…)     | Distributed as **Technical actions** per the ladder                                          |
| Test Plan                                 | Per-task tests under the task; story-wide strategy at story level; cross-story at epic level |
| ADR Impact                                | Epic header (epic path) / story header (story path)                                          |
| Tools used (SKILLS / MCP)                 | Epic footer (epic path) / story footer (story path)                                          |

### Technical action content spec

Each technical action (at any level) is specified with this shape — adapted from the former `make-plan` Step template. Use only the fields that apply; omit empty fields rather than padding them.

> - **Layer**: Domain | Application | Infrastructure | Presentation | Wiring | Migration | Test
> - **File path(s)**: Exact paths for files to create or modify.
> - **Types & Interfaces**: Classes, interfaces, enums, or type aliases introduced or changed, with full signatures.
> - **Behaviour**: Precise enough for a developer to implement without design decisions.
> - **Dependencies**: Which earlier technical actions (by task/story/epic id) this depends on.
> - **Notes**: Edge cases, idempotency, rollback strategy, references to existing code, third-party API citations (see rules below).
> - **Failure modes considered** — REQUIRED for any action whose Layer is `Infrastructure`, `Wiring`, or `Presentation`; OR any `Application` action introducing a new handler/use-case; OR any `Domain` action defining a port (interface). NOT required for pure Domain entity/value-object actions, pure DTO definitions, or migration-only actions. List the top 3 ways this action's integration surface could break or be misused later (silent recursion, double-registration, missing handler, race, leaky lifecycle, partial failure under iteration, error-translation gap between layers, etc.). For each, state whether the design eliminates the failure mode or whether a maintenance rule is documented inline. If ambiguous (could be pure Domain or could expose a port), default to including the block.

### Backlog template

> # Backlog — `<initiative title>`
>
> **Path**: epic | story
> **Status**: DRAFT | IN REVIEW | FINAL
> **Brief**: Reference to brief or task ID.
>
> --- _(EPIC HEADER — epic path only; omit entirely on the story path)_ ---
>
> ## Technology Choice
>
> _(Place FIRST when the work involves choosing between competing tools, frameworks, or approaches — readers MUST understand WHY before HOW. If no choice was made, replace with: "No technology evaluation required.")_
> When applicable, include: **Discovery** (search broadly — web search for current alternatives, emerging projects, recent benchmarks; aim for ≥4-5 candidates including niche/newer projects before narrowing), a comparison table (installation impact, performance, maturity, feature coverage, migration risk, rollback complexity), the decision with rationale (why this option wins for THIS project), and when each rejected alternative would be the right choice.
>
> ### Official Documentation Review
>
> After selecting a technology, read its official docs for the exact deployment method used in this project before writing any YAML/config/integration content. Do not rely on training data. Find the installation guide matching the project's deployment method (ArgoCD, Helm, Terraform, Docker Compose — not just generic `kubectl apply`); identify prerequisites (CRDs, namespace setup, secrets, permissions) and ordering constraints (sync-waves, init containers, dependency chains) and gotchas; capture exact registry URLs, chart names, versions, API groups, CRD kinds; cite the documentation URL for every tool-specific configuration value.
>
> ## Key Architect Decisions
>
> | #   | Decision | Rationale |
> | --- | -------- | --------- |
>
> ## Constraints
>
> Project-wide coding rules applying to every technical action in this backlog. Source from `architecture-rules`, `php-rules`, `make-tests`, and project-specific files under `.ai/<owner>/memory/active/`. Restate rules inline (do not link out) so a reader of any single task has all rules in view. Bullet list, no prose. Cite the source skill in each bullet. Required topics: type strictness (declarations, return types, generics); immutability defaults; naming conventions (classes, methods, files); security MUST / MUST NOT; testing rules (test-level placement, fixture style); any framework-specific lifecycle rules in scope.
>
> ## ADR Impact
>
> List new or updated ADR entries, or "None." Each affected ADR carries a one-line impact statement using one of: `new`, `superseded`, `extended`, `unchanged-but-cited`.
>
> ## Epic-level technical actions
>
> Cross-story / foundation technical actions per the scope ladder. Each in the **Technical action content spec** shape. Or "None — all technical actions resolve to a story or task."
>
> ## Stories
>
> | #                                                                                                                                                                                       | Story | Priority | Depends on | Sub-folder slug |
> | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | -------- | ---------- | --------------- |
> | One row per story from the stakeholder list — NEVER regroup, split, or merge. Each story's tasks and per-story/per-task technical actions live in that story's sub-folder `backlog.md`. |
>
> --- _(STORY HEADER — story path: place Technology Choice / Key Decisions / Constraints / ADR Impact here instead of an epic header. In the epic path the story sub-folder backlog repeats only the story-scoped subset.)_ ---
>
> ## Story: `<story title>`
>
> **Priority**: P0 | P1 | P2 … **Depends on**: `<other stories>` or none.
> One-paragraph description.
>
> ### Story acceptance criteria
>
> Story-wide acceptance criteria (those not owned by a single task). Flag gaps or ambiguities back to the orchestrator.
>
> ### Story-level technical actions
>
> Technical actions serving multiple tasks or story-wide scaffolding per the ladder. Each in the content-spec shape. Or "None — all technical actions resolve to a task."
>
> ### Tasks
>
> #### Task `<n>`: `<title>`
>
> **Priority**: … **Depends on**: `<other tasks>` or none.
>
> **Acceptance criteria**
>
> - …
>
> #### Technical actions
>
> The technical actions implementing exactly this task, each in the content-spec shape (Layer, File path(s), Types & Interfaces, Behaviour, Dependencies, Notes, Failure modes when required).
>
> _(repeat #### Task … for each task)_
>
> ## Test Plan
>
> For each acceptance criterion: test type (unit, integration, acceptance), file path, what is asserted. Per-task tests may instead live under their task; this section collects story-wide (and, in the epic header, cross-story) test strategy.
> **AC↔Test mapping**: the table maps acceptance criteria → test methods (one-way). A reverse `Test → AC` column is intentionally not required: acceptance test names are coarse by nature and forcing per-test AC references produces churn without catching defects; the AC column already provides reverse traceability.
> **Test-isolation enumeration — MUST**: if any test sources or executes the system-under-test (SUT) script as a whole (e.g. `bash bin/foo.sh` end-to-end, `. bin/foo.sh` to load definitions, or `source $SUT`) rather than calling specific functions in isolation, the backlog MUST enumerate the side-effects that execution fires during the test (per-app loops, network calls, filesystem mutations outside scratch dirs, subprocess spawns, side-effecting `set -e`/`trap` registrations) and EITHER (a) justify each as desired test behaviour with a one-line rationale, OR (b) design an isolation mechanism (marker-extraction sentinels + isolated `bash -c` source, env-gated branches like `[[ -n "${DEVBOT_INIT_TEST:-}" ]] && return`, function extraction into a sourceable helper, or test-only stubs on PATH) and document it alongside the test cases. **Sub-rule — transitive `set -u` audit**: when the isolation mechanism is "marker-extraction sentinels + isolated `bash -c` source" or "function extraction into a sourceable helper" AND the SUT runs under `set -u`, the backlog MUST list every shell variable the sourced block reads and verify each has a default (`${VAR:=…}` / `${VAR:-…}`) in the sourced block, the test harness, or an explicitly-listed auxiliary file; any auxiliary file needing defaults to be source-able under `set -u` MUST be named as in-scope, not "discovered during implementation".
> **Test-stub argv-capture format — MUST**: if a test stub intercepts a subprocess invocation and captures argv for assertion (e.g. a PATH-prepended fake `opencode` that logs how it was called), the backlog MUST specify token-per-line capture (e.g. `printf '%s\n' "$@"` between explicit `argv-begin`/`argv-end` delimiters) rather than token-per-space capture (`printf ' %q' "$arg"` loops or naive `"$*"`). Token-per-line surfaces quoting bugs as argv-count differences; token-per-space hides word-splitting defects.
>
> ## Tools used
>
> ### SKILLS
>
> Skills used while producing this backlog, or "None."
>
> ### MCP tools
>
> MCP tools used while producing this backlog, or "None."

## Design principles (technical actions)

Follow these when designing technical actions at any level:

- Analyze existing codebase patterns before proposing new ones. Prefer established conventions; document deviations in ADRs.
- Reference existing code as precedent. Legacy sections (defined in project-specific context files) MUST NOT be used as precedent.
- Specify Value Objects for domain concepts (names, IDs, scores, URLs, etc.).
- Port contracts MUST use typed DTOs — never raw arrays crossing boundaries.
- Port interfaces MUST NOT expose transport or infrastructure concepts.
- Application services returning data to presentation MUST return DTOs — never domain entities.
- Exceptions crossing layer boundaries MUST be defined at the port level.
- Design all event handlers and projections for idempotency.
- Every schema change needs a migration plan with a rollback strategy.
- When proposing to inline or remove an interface whose concrete declared `readonly class`, the backlog MUST include an explicit test-double strategy. Mockery cannot subclass readonly classes (engine fatal: `Cannot declare class … because parent class is readonly`). Acceptable strategies: (a) keep the interface and mock it; (b) drop the `readonly` modifier from the concrete; (c) provide a hand-written fake under `tests/Support/`. See `latent/global/ or latent/learnings/` — "Mockery cannot mock `readonly class`".

### Dependency verification strategy — MUST

When a technical action introduces system-level dependencies (CLI tools, interpreters, runtime executables) that `install.sh` or `update.sh` must verify, the backlog MUST include a **Dependency Verification Strategy** under the affected technical action (or, if cross-cutting, at the story/epic level per the ladder). For each dependency specify:

| Dependency | Verification method              | Install strategy                              | Rationale                      |
| ---------- | -------------------------------- | --------------------------------------------- | ------------------------------ |
| `<tool>`   | `command -v <tool>` / path check | `verify-only` (recommended) or `auto-install` | Why this method is appropriate |

- **`verify-only`**: script checks availability and exits with a clear error + installation instructions. Preferred for tools with multiple install paths (npm, pip, brew, apt).
- **`auto-install`**: script attempts automated installation via a single canonical method. Only acceptable when the tool has exactly one reliable install path across all supported platforms (Ubuntu, Fedora, macOS).

Rationale: omitting this strategy produces install scripts that either silently skip tools or attempt aggressive installs that fail in restricted environments. Critic MUST flag a missing strategy as WARNING (BLOCKER if an unverified dependency would cause runtime failure with no graceful fallback).

### Third-party library integration — MUST

When a technical action introduces a third-party library (any namespace not under the project's own root namespace), it MUST cite the source-of-truth for the namespace and any API symbol used. Acceptable cites: the library's `composer.json` autoload section with file path + line; OR the specific class file in the vendor tree with file path + class name; OR the library's official README/documentation URL with the symbol name visible at that URL. Hypothetical, recalled, or AI-completed API surfaces are forbidden — verify before writing. The cite belongs in the action's **Notes**. Cites are required for: namespace + class name (e.g. `ApprovalTests\Approvals` — NOT `Approve\Approvals`); method signatures called; configuration options set. A technical action introducing a third-party library without source-of-truth cites is a defect — critic raises it as BLOCKER and forces a re-spin.

### Third-party API reference marker — MUST

Every reference, anywhere in the backlog's technical actions, to a class, method, function, namespace, or file path under `vendor/` (or any namespace not under the project's own root namespace) MUST be either:

1. **Accompanied by an inline source citation** in the form `// per vendor/<pkg>/<file>:<line>` or `// per <official-doc-url>`, OR
2. **Preceded by a `[VERIFY: <gate-id>]` marker** referencing a verification gate (a technical action whose deliverable is the citation). Example: `[VERIFY: gate-B] $approver = new \Approvals\ApprovalRunner();` where gate-B is a technical action that produces a scratch note `vendor-approvals-api.md` enumerating available classes.

**Scope**: PHP core globals (`\Throwable`, `\Stringable`, `\DateTimeImmutable`, etc.) are exempt — they are part of the language, not third-party. The rule applies to any namespace whose top-level segment matches a `composer.json` `require` entry (excluding `php` and `ext-*`). The Pre-[FINISHED] Hygiene Gate mechanically enforces this; add an inline citation, add a `[VERIFY: …]` marker, or remove the reference.

### Import path trace — MUST

Every relative import path with 3+ `..` directory levels in a code sketch MUST be accompanied by a segment-by-segment directory trace from the file's own location to the target. The trace MUST: start at the importing file's directory; count each `..` as one level up; show the remaining path after the last `..`; confirm the resolved path matches the target's canonical location.

```
From <importing-file-path>:
 1 up → <directory-level-1>
 2 up → <directory-level-2>
 …
 N up → <resolved-parent>  ← then <remaining-path>
```

Rationale: import-path arithmetic errors are silent — wrong paths resolve to different files or to the project root, and dynamic imports (TypeScript `await import(...)`) fail silently in try/catch, leaving a hook disabled with no error. Critic MUST flag a missing trace as WARNING (BLOCKER if the import is the only path connecting two components and ambiguity would cause silent runtime failure).

### Verification-gate cross-referencing — MUST

When the backlog introduces a verification gate (a technical action a developer MUST execute before proceeding — a "scratch note" mandate, tooling-version check, third-party API surface confirmation), every downstream task or technical action whose correctness depends on the gate's outcome MUST reference the gate from its top line (first sentence, before any code, file paths, or sub-headings), phrased as a precondition:

> **Precondition**: Bus API verification gate (epic-level technical action G1) executed and scratch note exists.

Inline warnings later in the body are acceptable as reinforcement but not as the sole reference. A developer reading non-linearly MUST encounter the gate dependency at the same visual prominence as the task title.

## Procedure

### Step 0: Pre-flight

1. Read latent/ notes per `search-memory` skill. Include applicable lessons in all delegations.
2. **Check existing work folder**: list `.agents/memory/work/active/`. If a folder matches the current initiative, reuse it — NEVER create new. If multiple folders exist for the same initiative, consolidate into the correctly-named one and delete the duplicate.

### Step 1: Detect prompt shape

The orchestrator judges the prompt. NEVER delegate this. Use the table:

| Prompt shape                                                                                                                                                     | Path    | Next   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------ |
| Numbered/bulleted list of stories; OR `stories:`/`tasks:`/`features:` phrasing; OR NL enumeration of distinct features; OR cross-cutting; OR multi-step workflow | epic    | Step 5 |
| 1-3 files changed, clear scope, no ambiguity                                                                                                                     | trivial | Step 2 |
| Any other single brief                                                                                                                                           | story   | Step 3 |

**List rule**: each list item MUST be a candidate story (a coherent feature/change), not a sub-step of one story. Items reading as steps for one feature (e.g. "create model, write migration, add controller") = a single story → story path.

**Ambiguous**: ask the stakeholder — "One story or a list of separate stories planned as an epic?"

**Doubt rule**: prefer the story path. The cost of an unnecessary backlog is small; the cost of skipping planning on ambiguous work is large.

### Step 2: Trivial path

1. Skip backlog, technical plan, and critic review entirely.
2. Hand the brief + obvious context (file paths, patterns) directly to `implement-story`. Use `<work-folder>` as `<issue-folder>`.
3. The `implement-story` cycle (Tester → Developer → Reviewer per task) provides rigor. No planning artifacts produced.
4. Skip Steps 3–8.

### Step 3: Story path — Create the backlog skeleton

Delegate @po. The first sentence MUST be: `Write <work-folder>/backlog.md containing a prioritized task list with acceptance criteria for: <story brief>.`

- The PO produces the **product layer** of the combined backlog: the story header, tasks, per-task acceptance criteria, and priorities, in the **Backlog template** shape. The PO leaves the `#### Technical actions`, `### Story-level technical actions`, and `## Test Plan` sections present but empty (placeholder `_(architect to complete)_`) — these are filled in Step 4.
- The PO applies backlog rules from `src/instructions/agents/po.md`.
- The PO saves to `<work-folder>/backlog.md` with `**Status**: DRAFT`, signals [FINISHED] with the path.
- PO signals [NEEDS_INPUT] → relay to the stakeholder, re-delegate with the answer.

### Step 4: Story path — Technical implementation plan (folded into the backlog)

Delegate @architect. The first sentence MUST be: `Update <work-folder>/backlog.md in place with the technical implementation plan: add technical actions to each task, story-level technical actions, document-level technical content, and the Test Plan.`

- The architect produces a concrete directory tree mapping every source file to an assigned path, expressed as **File path(s)** across the technical actions (a Component Index table is acceptable in place of a full tree — see verbatim-bar rule).
- The architect writes the technical implementation plan **into `backlog.md`** following **Combined backlog format**: per-task `#### Technical actions`, `### Story-level technical actions`, the document-level technical content (Technology Choice, Key Decisions, Constraints, ADR Impact) in the story header, and the `## Test Plan`. The architect applies the **Technical-action scope-assignment ladder — MUST** to decide each action's level.
- There is NO separate `PLAN-ARCH-*.md`. The architect's deliverable IS the augmented `backlog.md`. The architect sets `**Status**: IN REVIEW` and runs the **Pre-[FINISHED] Hygiene Gate** (below) against `backlog.md` before signalling [FINISHED] with the path. The architect deliverable contract is defined in `src/instructions/agents/architect.md`.
- The orchestrator routes to @critic in Step 6.

#### Spike-during-planning rule

When the plan depends on a third-party API capability (plugin hooks, SDK features, undocumented runtime behavior) AND latent/ notes do NOT confirm the capability: instruct the architect to run a verification spike DURING planning, NEVER as Task 0 of implementation. A spike living in the backlog as a task = unverified architecture + a carried fallback design through review. Skip this rule only when the architect cites a latent/ note (gotcha, ADR, pattern) confirming the capability.

#### UI/UX review (if applicable)

Design work needed → delegate @designer. First sentence MUST be: `Write <work-folder>/DESIGN-YYYY-MM-DD-NNN.md …`. Designer saves the file and signals [FINISHED]. Skip if no design component.

### Step 5: Epic path — Write the epic backlog and plan each story

Prompt contains a list, cross-cutting concern, or multi-step workflow → epic path.

1. Delegate @po. First sentence MUST be: `Write <work-folder>/backlog.md containing an epic-level story breakdown for: <stakeholder list>.`
    - Epic backlog: **one entry per story from the user list** in the `## Stories` table. NEVER regroup, split, or merge — preserve the user structure.
    - Each entry: title, one-paragraph description, priority, dependencies on other stories in the list, sub-folder slug to create.
    - The PO saves to `<work-folder>/backlog.md`, signals [FINISHED] with the path.

2. For each story in the epic backlog, in priority order:
    1. Create the story sub-folder: `<work-folder>/YYYYMMDD-HHMMSS-NN-<story_slug>/`.
    2. Recurse the **story path** (Steps 3–6) for the story's combined backlog. Use the sub-folder as `<work-folder>` for the recursion.
    3. Output a progress report after each story:
        > **Epic planning progress**: \<planned\>/\<total\> stories planned | \<remaining\> remaining

All stories MUST be planned before implementation begins, making cross-story dependencies and architecture concerns visible before code.

**Epic-level technical actions**: as each story is planned, technical actions that the **scope ladder** assigns to the epic (cross-story foundation work, shared domain contracts, cross-cutting infrastructure, epic-wide migration ordering) are recorded in the epic `backlog.md` under `## Epic-level technical actions`, not duplicated into each story. Story sub-folder backlogs reference them by id where relevant.

Epic-level architecture review runs in **two phases**:

**Phase 1 — Early alignment review (after P0 stories)**

After the first two P0/P1 stories (typically those establishing shared contracts — command names, assembler classes, output paths, interfaces) are planned and at `Status: FINAL`:

1. Delegate @architect to review the planned stories + epic backlog together.
2. The architect identifies shared abstractions, naming conventions, contract interfaces, and output conventions that downstream stories will depend on.
3. The architect publishes an **Architecture Alignment Note** (`<work-folder>/architectural-alignment-YYYY-MM-DD-NN.md`) capturing key decisions downstream stories must follow, and records the corresponding epic-level technical actions in the epic `backlog.md`.
4. The orchestrator forwards this note as context when delegating each remaining story plan.

**Story context-forwarding rule — MUST**: when delegating each remaining story plan to the architect (after Phase 1), include the Architecture Alignment Note (or an explicit list of key decisions — command names, output paths, interface names, assembler class names) as context, prefixed:

> **Established context**: [key decisions from the alignment note]

**Phase 2 — Final reconciliation review (after all stories)**

After all stories are planned:

1. Delegate @architect to review the full epic — all story backlogs + their technical plans together.
2. The architect identifies shared abstractions, migration ordering, cross-story dependencies, and integration risks.
3. The architect recommends changes → update affected story backlogs (and the epic-level technical actions) before proceeding.

Skip Steps 3–4 and 6 at the epic level (they execute inside each story recursion). Continue to Step 7.

### Step 6: Critic review loop

Delegate @critic. First sentence MUST be: `Write <work-folder>/PLAN-REVIEW-YYYY-MM-DD-NNN.md reviewing <work-folder>/backlog.md (product decomposition AND technical actions).`

- The critic reviews the **combined `backlog.md`** — both the task/AC decomposition and the technical actions — and saves to `<work-folder>/PLAN-REVIEW-YYYY-MM-DD-NNN.md` per `review-plan` skill (NEVER use a `CRITIC-*.md` prefix).
- Address necessary issues. Justify issues not addressed.
- After fixes, update `backlog.md` in place so the task list, technical actions, file paths, and code sketches stay consistent. Change `Status` from `DRAFT`/`IN REVIEW` to `FINAL` when the critic loop concludes with zero BLOCKERs.
- **Post-revision format-md — MUST**: after any architect revision to `backlog.md` (whether addressing critic findings or self-correcting), the orchestrator MUST run `format-md` on the work folder before re-delegating to the critic. Table misalignment after edits masks content errors and slows review. This step is the orchestrator's responsibility, not the architect's.
- Stall or goal shift → terminate the loop, ask the stakeholder for direction.
- Iterate until no issues remain.

#### Review/revision state-transition table — MUST

The planning state machine has exactly four legal transitions out of any critic verdict. The orchestrator MUST consult the table after every critic round and select the unique matching row.

| Critic verdict         | Has unresolved findings? | Next state | Next delegation                                                     |
| ---------------------- | ------------------------ | ---------- | ------------------------------------------------------------------- |
| APPROVED               | No                       | FINAL      | (none — orchestrator promotes per `devbot.md` FINAL-promotion gate) |
| APPROVED               | Yes (any severity)       | IN REVIEW  | architect (revision cycle for new findings)                         |
| CHANGES REQUESTED      | (always)                 | IN REVIEW  | architect (revision cycle for all findings)                         |
| CONDITIONALLY APPROVED | (always)                 | IN REVIEW  | architect (revision cycle for unmet conditions)                     |

**Forbidden transition (MUST NOT)**: consecutive critic rounds without an intervening architect revision. If the previous round returned CHANGES REQUESTED, CONDITIONALLY APPROVED, or APPROVED-with-findings, the orchestrator MUST delegate a revision to the architect before any further critic delegation. A "second opinion" review requires the architect to first produce a Review Response explaining why no changes are needed (which counts as the intervening revision).

**Confirming-review feedback handling — MUST**: a confirming critic round (the round after the architect addresses prior BLOCKERs) may return `APPROVED` while surfacing new findings (any severity). When this happens, do NOT transition to `Status: FINAL`. Re-delegate the architect for one resolution pass whose deliverable is the updated `backlog.md` + an addition to the Review Response section recording, for each new finding, either the fix applied (cite line range/section) or an explicit dispensation (cite finding id + severity + one-line rationale). After the pass, the orchestrator verifies the Review Response covers every new finding, then transitions to `Status: FINAL` without an additional critic round. A confirming review returning `APPROVED` with zero new findings transitions directly to `Status: FINAL`.

### Step 7: Closing — Summary and approval

1. Create `<work-folder>/summary.md` per `summarize_plan` skill.
2. Output the summary to the stakeholder, ask for final approval.
3. Write `<work-folder>/planning-complete.md` as the final closing-checklist artifact, listing each required artifact with **existence-verified AND canonical-path-verified** status. This file MUST be the orchestrator's last write before reporting completion.

    Each `[x]` line MUST cite the **canonical SKILL-prescribed path** under `<work-folder>` (resolved to the absolute path of the work folder) AND a **verifying tool call** confirming the file at that path. Existence-only checks not binding the file to its canonical path are invalid — the line MUST remain `[ ]` until the file is at the correct path.

    Required artifacts by path:

    **Story path**:
    - `<work-folder>/backlog.md` — refined; every task has acceptance criteria + priority + technical actions; story-level and (where applicable) document-level technical content present; `**Status**: FINAL`, set by the orchestrator only after the critic round is APPROVED with zero BLOCKERs.
    - `<work-folder>/PLAN-REVIEW-YYYY-MM-DD-NNN.md` — at least one with verdict APPROVED dated after the latest architect revision.
    - `<work-folder>/summary.md` — per `summarize_plan` skill.
    - `<work-folder>/retrospective/planning.md` — per `make-retrospective` skill.

    **Epic path**:
    - `<work-folder>/backlog.md` — epic backlog, one entry per story from the user list, plus `## Epic-level technical actions`.
    - `<work-folder>/summary.md` — epic planning summary.
    - `<work-folder>/retrospective/planning.md` — per `make-retrospective` skill.
    - For each story sub-folder, the **Story path** required artifacts above (verified inside the sub-folder).

    **Trivial path**: no `planning-complete.md` produced. No planning stage. Proceed direct to implementation.

    For each artifact, the orchestrator MUST `read` it at its canonical path (or `ls` the directory + confirm a non-empty file at that path) BEFORE listing `[x]`. Proof is a tool call against the canonical path, not an assertion.

    Verification format — each `[x]` line MUST take this shape:

    - [x] `<canonical-path>` (verified by `<tool>` at `<ISO-8601 timestamp>` — `<evidence>`)

    Example body:

    ```markdown
    # Planning complete — 20260508-143000-01-pokeapi-bus-refactor

    Work folder: `.agents/memory/work/active/20260508-143000-01-pokeapi-bus-refactor/`
    Path: story
    Verified at: 2026-05-08T15:30:00Z

    - [x] `.ai/.../20260508-143000-01-pokeapi-bus-refactor/backlog.md`
          (verified by `read` — Status: FINAL on line 3; 7 tasks, each with Technical actions)
    - [x] `.ai/.../20260508-143000-01-pokeapi-bus-refactor/PLAN-REVIEW-2026-05-08-002.md`
          (verified by `read` — verdict: APPROVED on line 3)
    ```

    An artifact NOT at its canonical path → the line is `[ ] <canonical-path> — NOT AT CANONICAL PATH (found at <actual-path>)` or `[ ] <canonical-path> — MISSING`. The orchestrator treats the planning stage as [PARTIAL] per the closing gate below. Move the file to its canonical path, re-verify before marking `[x]`. Planning is complete only when this file exists + lists every required artifact `[x]` at its canonical path with a verifying tool call.

#### Complete-side enumeration — MUST

The closing checklist + summary are sound-side AND complete-side. Sound-side (established by canonical-path verification above): every listed artifact MUST exist on disk with a verifying tool call. Complete-side (this rule): every produced artifact in the work folder MUST appear in the listing.

**Step 7 procedure addendum**:

1. Run `glob` for `PLAN-REVIEW-*.md` in `<work-folder>` (recursive in story sub-folders for the epic path). Each match: the closing checklist (`planning-complete.md`) + summary (`summary.md` Artifacts Produced table) MUST contain one entry naming the file, its verdict (APPROVED / CHANGES REQUESTED / CONDITIONALLY APPROVED), and a one-line role (`superseded`, `latest-approved`, `confirming`, `orphan-investigation-required`).
2. Run `glob` for `backlog.md` in `<work-folder>` (recursive for the epic path). Each MUST appear in the closing checklist with its `Status` and role (epic backlog / story backlog).
3. Run `glob` for any other `*.md` artifact in `<work-folder>` (summary, retrospective, alignment note, scratch). Each MUST appear in the closing checklist either as a required artifact or as `not required by skill — present for context`.
4. Any `glob` match unlisted in `planning-complete.md` after steps 1–3 → gate FAIL. The orchestrator MUST add the missing entry (with role + verifying tool call) before proceeding.

**Audit-log enumeration (MUST)**: `interactions.md` MUST contain one Delegation entry per producing subagent invocation:

- Each `PLAN-REVIEW-*.md` file → `interactions.md` MUST have ≥1 critic Delegation entry whose deliverable matches the file path.
- Each `backlog.md` → `interactions.md` MUST have ≥1 PO Delegation entry (created the product decomposition) AND, where the backlog contains technical actions, ≥1 architect Delegation entry (folded in the technical plan) plus one architect entry per recorded revision in the Review Response section.

A produced deliverable with no corresponding Delegation entry → the orchestrator MUST add the missing entry (citing the deliverable path as evidence, tagged `RECONSTRUCTED FROM ARTEFACT`) before the closing-checklist gate passes.

#### Per-Agent Totals reconciliation across all closing artefacts — MUST

Every agent-count claim in ANY closing artefact (`summary.md`, `retrospective/planning.md`, `retrospective/implementation.md`, `planning-complete.md`, and any other `<work-folder>/**/*.md` produced at the closing-checklist stage) MUST reconcile against the count of Delegation entries in `interactions.md` per agent role.

**Procedure**:

1. Compute `delegation_count[agent]` from `interactions.md` (one count per role: PO, architect, critic, tester, developer, reviewer, designer).
2. Compute `deliverable_count[agent]` from `glob` per the agent's expected deliverable pattern:
    - critic: `glob` for `PLAN-REVIEW-*.md` in `<work-folder>`.
    - PO: `glob` for `backlog.md` (+ any `backlog-delta-*.md`) in `<work-folder>`.
    - architect: count of `backlog.md` files containing a Technical actions / technical-plan section, PLUS the count of architect-revision entries in any `Review Response` section. (The architect no longer produces `PLAN-ARCH-*.md`; the technical plan lives in the backlog.)
    - Other agents: `glob` for the agent's expected deliverable pattern.
3. Confirm `delegation_count[agent] >= deliverable_count[agent]` for each subagent. Any agent with `delegation_count < deliverable_count` → the orchestrator MUST add the missing Delegation entries (citing the produced deliverable) before the gate passes.
4. For each closing artefact, `grep` for any agent-count claim (patterns: `\d+ (PO|architect|critic|tester|developer|reviewer|designer)`, `Total subagent invocations: \d+`, any Per-Agent Totals cell).
5. For every match, verify the cited number equals `delegation_count[agent]` (or the sum for a "Total"). Mismatches FAIL the gate.
6. The orchestrator MUST update mismatched artefacts with reconciled counts, annotate reconstructed entries `RECONSTRUCTED FROM ARTEFACT`, and cite the source-of-truth (delegation count from `interactions.md`).
7. Update the Per-Agent Totals table in `interactions.md` to reflect reconciled counts.

#### Planning Stage completion gate — MUST

The Planning Stage is NOT complete — the orchestrator MUST NOT proceed to Step 8 — until `<work-folder>/planning-complete.md` exists, written by the orchestrator as the final action of Step 7, listing every required artifact `[x]` with a verifying tool call (read or ls). This mirrors the @tester gate pattern: completion claims are not trusted; the artifact MUST exist on disk and verification MUST be a tool call, never narration. If `planning-complete.md` is missing or any item is `[ ]`, treat the planning stage as [PARTIAL] and complete the missing step(s) before proceeding. **Each `[x]` line MUST cite the canonical SKILL-prescribed path under `<work-folder>`; existence-only verification not binding the file to its canonical path is invalid and the line MUST remain `[ ]`.** The gate does not apply to the trivial path.

### Step 8: Transition

On approval:

1. Produce a post-planning retrospective per `make-retrospective` skill.
2. Address retrospective findings per `address-retrospective` skill — pass the retro file path.
3. Proceed to implementation:
    - **Story path**: follow `implement-story` skill once, with `<work-folder>` as `<issue-folder>`. The combined `backlog.md` is the implementation source — tasks carry their technical actions inline.
    - **Epic path**: follow `implement-story` for each story in dependency-respecting order, with the story sub-folder as `<issue-folder>`. After each story, output:
        > **Epic implementation progress**: \<implemented\>/\<total\> stories done | \<blocked\> blocked | \<remaining\> remaining
    - **Trivial path**: already routed in Step 2; nothing more here.

Ordering rules (epic path): respect explicit dependencies in the epic backlog; no deps → priority order; foundation stories (shared domain, infra, config) before consumers; same bounded context → sequential.

#### Epic completion (when the epic path was taken)

All stories implemented:

1. Run the full test suite to verify cross-story integration.
2. Produce a post-epic retrospective per `make-retrospective` skill. Save to `<work-folder>/retrospective/implementation.md`.
3. Address retrospective findings per `address-retrospective` skill — pass the retro file path.
4. Notify the stakeholder with a completion report covering all stories + recommended next actions.
5. Follow `remember_task` skill to capture lessons learned from the epic.
6. Archive the work folder: move `<work-folder>` from `.agents/memory/work/active/` to `.agents/memory/work/archive/`, preserving the name.

## Pre-[FINISHED] Hygiene Gate

The architect runs this gate against `backlog.md` (the combined document) before signalling `[FINISHED]` for the technical-plan augmentation (Step 4), and again after each revision (Step 6). Report each result in the [FINISHED] message.

### Hygiene Gate output enumeration — MUST

The [FINISHED] message MUST enumerate per-item evidence for each check, not summary counts. Specifically:

- **Item 4 (algorithm↔test traceability)**: enumerate per traced / behaviour-change / under-specified row.
- **Item 5 (verbatim-bar)**: instead of "N lines, M blocks", produce a table:

    ```

    ```

| Line range | Block type     | Length | Justification (verbatim because …) |
| ---------- | -------------- | ------ | ---------------------------------- |
| 102–161    | directory-tree | 60     | navigability for implementer       |
| 686–748    | code-sketch    | 63     | task-T13 wiring, three-way trace   |

```

- **Item 6 (third-party API references)**: instead of "N refs, M markers", produce a table:

```

| Line | Reference            | Status                                     |
| ---- | -------------------- | ------------------------------------------ |
| 614  | \GetE\Bus\MessageBus | [VERIFY: gate-bus-api]                     |
| 632  | \Approvals\Approver  | inline cite: vendor/approvals/.../A.php:42 |

```

An empty table = an explicit "no third-party references" claim.

- **Item 7 (ADR Impact)**: enumerate the ADR identifiers found and the section's per-ADR rows.

The orchestrator MUST verify the [FINISHED]-message tables against `backlog.md` (one `grep` per claimed line range) before accepting the [FINISHED] signal. A [FINISHED] message with summary counts instead of enumerated tables is invalid; the orchestrator MUST return `[BLOCKED] hygiene_gate_output_unverifiable — enumerate per-item evidence per plan SKILL Hygiene Gate output enumeration rule` and re-delegate.

### Checklist

Before signalling `[FINISHED]`, the architect MUST run this checklist against `backlog.md` and report each result:

1. **Self-revision residue grep** — search the backlog for: `Wait`, `Actually`, `let me re-`, `let me fix`, `let me redo`, `simplest approach`, `On reflection`, `Hmm`. Report the match count. **Must be 0** outside fenced code blocks. If matches are found, edit them out before signalling [FINISHED].
2. **Single-version check** — confirm no task or technical action appears twice with conflicting content (e.g. "Task 7 (revised)" alongside "Task 7"). Report yes/no.
3. **Trade-offs format** — alternatives appear only inside `Trade-offs considered` subsections, never as inline "but actually X is better" passages. Report yes/no.
4. **Algorithm ↔ test traceability** — for every Test Plan row referencing algorithm or value-object behaviour defined elsewhere in the backlog (or in original source being refactored), trace at least one expected value back to the algorithm sketch or original script line. If the test expectation does not match what the algorithm/script would produce for that input, the test is wrong (the plan MUST preserve behaviour being refactored). Either correct the expectation, or explicitly mark the test as a *behaviour change* with rationale. If an expectation cannot be traced to a deterministic source (algorithm sketch line, original code line, AC text), it is under-specified and MUST NOT ship. Report `traced` / `behaviour-change marked` / `under-specified` counts.
5. **Plan-size check** — count lines (`wc -l`). If the backlog exceeds 900 lines for a single-component scope, identify every code sketch over 30 lines. For each: either summarise as `### Behaviour` (bulleted) + `### Contract` (signatures only) + `### Implementation file` (path reference), removing the full body; OR justify verbatim inclusion with a **discriminating** one-line reason in the technical action's `**Notes**`. A discriminating justification cites a property that does NOT generalise to other verbatim blocks in the same backlog. Generic phrases ("exact assertion values required", "contract MUST be precise", "needed for clarity") do NOT discriminate and are invalid. Valid examples:
 - "complex sort algorithm with non-obvious pivot selection — prose ambiguous"
 - "byte-identical approval test fixture — any whitespace change breaks the test"
 - "regex with 4 lookarounds — escaping rules differ across PHP versions"
 - "exact exception class hierarchy required because PHPUnit's `expectException` checks `instanceof`, and the inheritance chain is contested in the backlog"

 A justification that could be copy-pasted onto a different block in the same backlog is, by definition, not discriminating.

 Specific block types that do NOT pass the discriminating bar by default and MUST be summarised rather than included verbatim, unless the architect cites an additional contract-bearing property the standard binding does not capture:

 - **Directory trees** — the contract is in PSR-4/namespace declarations + the File path(s) of technical actions; the tree is convenience. Default to a textual summary (e.g. "Component groups: X, Y, Z; ports under `Core/Port/<Component>/`; see PSR-4 autoload at line N") plus the PSR-4 block. A tree passes the bar only if the architect cites a property the standard binding does not capture (e.g. "non-standard layout deviates from PSR-4 in module M and the deviation MUST be reviewed line-by-line").
 - **Configuration scaffolds** (`composer.json`, `phpunit.xml`, framework config) — the contract is the version-pinned dependency or named extension; surrounding structure is boilerplate. Pass the bar only if a specific non-default key requires byte-identical reproduction (cite the key by name).
 - **Generated boilerplate** (autoload classmaps, full migration up/down stubs) — never pass the bar.

 When a tree or config block is only a convenient way to communicate component grouping, prefer a small **Component Index** table (component name → directory path → kind) over a full tree.

 When the backlog exceeds 900 lines, the architect MUST add a **Verbatim Inventory** section near the top (immediately after Technology Choice) listing every verbatim block ≥30 lines:

| Location | Block                 | Lines | Discriminating justification                     |
|----------|-----------------------|-------|--------------------------------------------------|
| Task 1   | `GrowthRate` enum     | 32    | exact case-name strings used as DB column values |
| Task 8   | `LevelCalculatorTest` | 84    | byte-identical approval-test fixture             |

 Inline implementations are a smell — the developer's workspace is the place for full implementations, not the backlog. The backlog describes contracts and behaviour; the developer writes the implementation. The 900-line threshold is calibrated on observed kata-scope plans (clean ≈800, bloated ≥1000).

 **Revision-time verbatim-bar re-check (MUST)**: if the backlog being signalled [FINISHED] is a **revision** (the file has prior `## Review Response` sections and the current line count exceeds the most recent prior [FINISHED] count by >25%), the architect MUST re-run the discriminating-bar check on every code block, directory tree, configuration excerpt, and namespace listing. For each block ≥30 lines (code) or ≥5 lines (tree/config/listing), either **re-justify** with an inline `# Verbatim because <reason>` comment if it was added or grew during the revision, OR **remove** it in favour of a citation or summary. Report:

```

Verbatim-bar revision re-check: <N> blocks evaluated, <M> re-justified, <K> removed. Backlog size: <prior> → <current> lines (Δ +X%).

```

If growth ≤25%, the re-check is optional but recommended; if >25%, mandatory. If the revised backlog exceeds the 900-line soft ceiling AND growth is >25%, the re-check is a precondition for [FINISHED].
6. **Third-party API reference verification** — every reference to a third-party namespace (per **Third-party API reference marker — MUST**) MUST carry either an inline `// per …` citation OR a `[VERIFY: <gate-id>]` marker. Run:

```

grep -nE '(\\\\[A-Z][a-zA-Z0-9_]+\\\\|new \\\\?[A-Z])' <backlog-file> \
| grep -v '^[^:]_:[^/]_//' \
| grep -v '\[VERIFY:'

````

Any line in the output is an unverified third-party reference. The check FAILS if any such line is found and not exempt (PHP core globals exempt). Report the match count and exempt-line count separately.
7. **ADR Impact section presence** — the gate FAILS if the backlog satisfies any of these triggers AND lacks an `## ADR Impact` section:
1. The Key Architect Decisions table has ≥3 rows.
2. Any body text references an ADR identifier matching `\bADR-\d{3,}\b`.
3. The backlog introduces a new architectural pattern (port interface, new layer, new bounded context) — detectable via Constraints or a Glossary section.

 The ADR Impact section MUST enumerate each affected ADR with a one-line impact statement using one of: `new`, `superseded`, `extended`, `unchanged-but-cited`. Mechanical check:

 ```
 if grep -qE '(\bADR-[0-9]{3,}\b)' <backlog-file> && ! grep -q '^## ADR Impact' <backlog-file>; then
   FAIL: ADR identifier referenced but no ADR Impact section
 fi
 ```

 **ADR-existence verification** — after confirming the section exists, for each ADR identifier cited (excluding those marked `new` — which need creation, not prior existence — and excluding inline restatements without numbered identifiers like `no ADR — pattern documented in`), verify the ADR exists at its canonical path. The canonical ADR vault is `latent/ADRs.md` (project root `.agents/memory/latent/ADRs.md`). Verification:
 - `grep` for each cited ADR identifier (e.g., `grep -c 'ADR-007' .agents/memory/latent/ADRs.md` → must return ≥1).
 - If an ADR identifier returns 0 matches, the gate FAILS. The architect MUST either (a) create the ADR in `latent/ADRs.md` before signalling [FINISHED], (b) replace the citation with an inline restatement of the constraint and source (existing source file path), or (c) add a `[RESOLVE: <gate-id>]` verification gate marker if the ADR must be created as part of implementation.
 - Inline restatements without numbered ADR identifiers (`no ADR — documented in <source>`, `unchanged-but-cited` with source file path) are EXEMPT from existence check — they are not phantom citations.
 - Report: for each ADR identifier cited, status (`exists`, `created-now`, `replaced-with-inline`, `verification-gate-created`, or `phantom-fail`). Zero `phantom-fail` entries required to pass.

8. **Cross-platform portability check** — every external command (`md5sum`, `sed -i`, `grep -P`, `readlink -f`, etc.) in any bash code sketch or behaviour description outside a `# linux-only` or `# macOS-only` guard MUST be checked against macOS availability. Linux-only commands (`md5sum`, `realpath`) MUST be replaced with portable alternatives (`shasum -a 256` or `tr` for hashing; `perl -MCwd -e 'print Cwd::abs_path shift'` for realpath) OR wrapped in platform-detection logic. Report: all external commands found; each command's status (`portable`, `guarded`, or `unchecked`); zero `unchecked` entries required to pass.
9. **Language syntax verification** — every non-standard type syntax or language construct in code blocks or type declarations (generic closure signatures `\Closure(T): R`, intersection types `TypeA&TypeB`, union types with unsupported combinations, readonly-property-pattern syntax specific to un-released PHP versions, etc.) MUST be verified against the official PHP documentation or the project's `composer.json` `require.php` version. If the syntax is not valid for the project's PHP version, replace it with the correct equivalent (e.g. `\Closure` for native type, `@param \Closure(T): R` for PHPDoc callable signature) and add an inline comment documenting the resolution. Report: every non-standard syntax found; each entry's status (`verified-valid`, `corrected`, or `no-non-standard-syntax-found`). Zero `uncertain` entries required to pass. PHP core types (`string`, `int`, `array`, `callable`, etc.) and standard intersection/union types from the project's PHP version are exempt.
10. **Third-party YAML config key verification** — for every YAML configuration snippet referencing a third-party receiver, processor, exporter, or extension (OpenTelemetry collector components, Kubernetes resource specs, Helm chart values), the architect MUST verify the exact key names, values, and required fields against the official documentation URL cited in the action's `**Notes**`. This check is required when the YAML uses identifiers under `vendor/` namespaces, OTel component names (`kubeletstats`, `k8s_events`, `k8sattributes`, `prometheus`, `filelog`, `hostmetrics`, `file_storage`, etc.), or any key-value pair documented at a URL in the action's Notes. Report: every YAML block found; for each, the documentation URL verified against; status (`docs-matched`, `inline-citation-only`, or `unverified`). Zero `unverified` entries required to pass. YAML blocks whose keys are fully enumerated in the same technical action's `**Behaviour**` with explicit per-key documentation citations are exempt.
11. **Dockerfile PECL build-dependency verification** — for any technical action that adds a `pecl install` command to a Dockerfile, verify that the RUN block includes build tool installation (`apt-get install -y $PHPIZE_DEPS`) BEFORE the `pecl` command, OR that the architect has verified the base image includes build tools and documented the verification with a URL or file-path citation in the action's `**Notes**`. This check catches the common pitfall where a production Dockerfile purges `-dev` packages before the PECL step and the base image lacks build tools (`autoconf`, `gcc`, `make`, `pkg-config`). Report: every Dockerfile `pecl install` reference found; for each, the build-tool strategy (`install-before-compile`, `base-image-includes` with citation, or `unverified`). Zero `unverified` entries required to pass.
12. **Latent note reference resolution** — for every `[latent <path>]` reference in Known gotchas sections (matching `\[latent\s+[^\]]+\]`), verify the referenced file exists via `read` or `glob`. Report: every reference found; each entry's status (`resolved` — file exists at cited path, or `dead` — file not found). Zero `dead` entries required to pass. If a reference is dead, either (a) create the latent note with the cited content, or (b) change the citation to `[prompt context]` if the information was sourced from the orchestrator prompt rather than a latent file. Latent references to `global/` directories under `.agents/memory/latent/` are valid; references to non-existent directories fail.

Format in the [FINISHED] message:

> Hygiene gate (against backlog.md):
> 1. Residue grep: 0 matches
> 2. Single-version: yes
> 3. Trade-offs format: yes
> 4. Algorithm↔test traceability: N traced, M behaviour-change marked, 0 under-specified
> 5. Plan-size check: NNN lines (≤900: pass | >900: Verbatim Inventory present? yes/no; discriminating-justification audit: M blocks total, K passed, 0 MUST remain failed)
> 6. Third-party API references: K matches, J exempt, 0 unverified
> 7. ADR Impact: T identifiers found, section present? yes/no, existence verified: K ok / 0 phantom, pass/fail
> 8. Cross-platform: C commands, 0 unchecked
> 10. YAML config keys: K blocks verified, 0 unverified
> 11. Docker PECL deps: K pecl references, 0 unverified
> 12. Latent references: N references, 0 dead

A [FINISHED] signal that omits this block, or reports any failure without an accompanying fix, is invalid. The orchestrator MUST treat it as `[PARTIAL]` and re-delegate with the failing items called out.

### Review Response Template

When responding to critic feedback on the backlog:

> - **Changes Made**: list of updates to the backlog.
> - **Unaddressed Feedback**: justification for each omission.
> - **Backlog Deltas**: list every task whose contract changed as a result of this revision (return type, method signature, included VOs/DTOs, acceptance-criteria text). For each delta state: the task number and short title; the old contract (one line, quoted from the current backlog); the new contract (one line, matching the revised technical actions); and a classification — `contract-shape` (signature/return-type/structural) or `documentation-only` (wording, typos, references). If no tasks are affected, write: "No backlog deltas — revision is internal to the technical actions."

Because the backlog and the technical plan are now the **same document**, a contract change in a technical action and the task it serves are co-located. The architect updates the task's acceptance criteria and the technical actions together in `backlog.md`; the Backlog Deltas section is the audit trail of those co-located changes (no cross-document reconciliation to a separate `PLAN-ARCH` is needed).

A [FINISHED] signal that omits the `Backlog Deltas` line is invalid. The orchestrator MUST treat it as `[PARTIAL]` and re-delegate with the missing item called out.

#### Revision-time backlog reconciliation — MUST

When the architect revises the backlog in response to critic findings, the Review Response's `Backlog Deltas` section enumerates every task whose contract changed. For each `contract-shape` delta, the architect MUST ensure the task's acceptance criteria, description, and technical actions are mutually consistent within `backlog.md` before signalling [FINISHED] — this is a precondition of the revision being complete, not optional documentation. Rationale: without it, a task's stated goal drifts from the technical actions meant to achieve it, and downstream implementation inherits stale acceptance criteria.

Exception: if the revision makes zero contract changes (all findings were documentation-only), write "No backlog deltas — revision is internal to the technical actions."

## Exception Handling

- Unexpected situation → use `exception-handling` skill for structured recovery.
- A story cannot be planned or implemented due to a dependency on an unfinished story → mark [BLOCKED] in the epic backlog, continue with the next eligible story.
- The orchestrator may terminate early: requirements change, work deprioritized, stakeholder requests a pivot.
- Scope grows during planning → pause, ask the stakeholder whether to expand the work or split off additional initiatives.
````
