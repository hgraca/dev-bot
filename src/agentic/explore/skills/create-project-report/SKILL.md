---
name: devbot:create-project-report
description: "Explores the entire project and produces a technical description at .agents/memory/active/project.md covering structure, purpose, architecture, conventions, and known inconsistencies, plus a preemptive-skill-loading list. Use this skill whenever onboarding to a new project, when the description is missing or stale, when the user says 'explore the project', 'describe the project', 'map the codebase', 'document the architecture', or invokes /devbot:create-project-report — and when starting work on an unfamiliar repo before planning."
---

# Skill: Explore Project

Produce concise, technical project description any agent or human can load at session start to understand
_what this project is_, _how laid out_, and _where rough edges are_. Output: two files —
`.agents/memory/active/project.md` (project map) and `.agents/memory/active/preemptive-skill-loading-list.md`
(skills manifest for future sessions).

This is one-page map, not findings report. Rough edges
named in one line each so future work has context — diagnosing and fixing them out of scope.

## When to Apply

- New project initialised and `description.md` missing or empty.
- Existing `description.md` stale (repository drifted significantly).
- User explicitly asks to explore, describe, or map project.
- Before planning large initiative in unfamiliar codebase.

## Procedure

### Step 1: Check existing state

Read `.agents/memory/active/project.md` and `.agents/memory/active/preemptive-skill-loading-list.md`
if they exist. Treat every claim in both files as hypothesis to verify against codebase (source of truth).
Note assertions to confirm, refute, or update during exploration. If either file exists, the goal is
**update where necessary**, not replace wholesale — preserve accurate content, fix stale claims, add
new observations. If a file does not exist, create it during its corresponding step.

### Step 2: Survey repository

Build mental model by reading files in this order. Stop expanding into folder once its purpose clear —
exhaustive reads wasteful.

0. **Knowledge graph (if available)**: if `graphify-out/graph.json` exists, query graph first for fast
   architectural overview — compresses relationship-heavy parts into few calls.
   Run `graphify_graph_stats` MCP tool to confirm graph populated and surface god nodes, communities, and stats.
   Then use `graphify query "<question>"` (CLI) or MCP tools (`graphify_god_nodes`,
   `graphify_graph_stats`, `graphify_query_graph`) for concept-level questions (e.g. "entry points",
   "data stores", "auth"). Treat graph output as hypothesis layer — still verify against codebase.
   If `devbot:graphify` unavailable or graph empty/stale, skip and proceed with file-based survey.
   See `devbot:graphify`.
1. **Top-level orientation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `Makefile`, `package.json` / `composer.json` /
   `pyproject.toml` / `Cargo.toml`, `.gitignore`, `docker-compose.yml`, `.env.dist`.
2. **Directory shape**: list root and one level deep. Identify which folders hold source, tests, config,
   scripts, docs, vendored code, runtime data.
3. **Entry points**: scripts in `bin/`, `scripts/`, `cmd/`, framework bootstraps (`public/index.php`,
   `src/main.ts`, `manage.py`, `main.go`, …).
4. **Architecture artefacts**: `docs/architecture*.md`, ADRs (`docs/adr/`, `.ai/adr/`), `.agents/memory/latent/ADRs/`,
   `.agents/memory/latent/PDRs/`.
5. **Source tree**: sample one or two representative files per major component to confirm patterns (layering,
   naming, framework usage). Use `repomix` or `codebase-peek` to bulk-scan when many files belong to same
   concern — see `search-code` for tool selection.
6. **Tests**: locate test root, identify framework, note layering convention (unit/integration/e2e).
7. **CI/CD**: `.github/workflows/`, `.gitlab-ci.yml`, Jenkins — identify which CI is used, which workflows/jobs exist, what each tests or does (lint, static analysis, unit/integration/e2e tests, build, deploy), and what manual actions are available (`workflow_dispatch`, retry, deploy buttons). Also note `Makefile` targets and lint/format config.
8. **Runtime & deployment**: how the project runs and ships — the runtime (Docker, Kubernetes, serverless, bare metal), deployment manifests/Helm charts (`k8s/`, `deploy/`, `helm/`, ArgoCD), `Dockerfile*`/`docker-compose.yml`, and what a deploy actually does. Also note whether merging to the default branch automatically deploys (merge == deploy).

Prefer broad coverage over depth. If folder gitignored or marked `no-vcs`, skip (see `ignore.md`).

**`.ai/` directory**: holds agent-only artefacts (memory vault, planning issue folders,
thinking/scratch, project rules). **Gitignored by convention** — nothing under `.ai/` committed to
project repository. Treat as local working state for agents, not as project source. When writing
description, mention `.ai/` under _Repository layout_ (one row, noting "agent working state, gitignored")
and under _Critical conventions_ (rule that `.ai/` contents never committed). Do not enumerate its
sub-structure — that belongs to `devbot:memory-management`.

**Memory vault — committed to git or not?**: determine whether the project's memory vault is under version
control. The vault lives at `<devbot_dir>/memory/` (default `.agents/memory/`; `devbot_dir` comes from
`.devbot.project.jsonc` / `.devbot.global.jsonc`). Run `git ls-files <devbot_dir>/memory/ | head`: non-empty
output means the vault is git-tracked (memory files are committed); empty means it is gitignored (not
committed). The `commit_memory` key in `.devbot.project.jsonc` / `.devbot.global.jsonc` is the intended
signal (`true` = committed, absent/`false` = not). Record the outcome in the description under _Critical
conventions_ so future agents know whether to commit memory files — if the vault is not tracked, they must
never `git add` it.

### Step 3: Identify what may be problematic

While exploring, capture observations under these categories. **Be specific** — cite paths. **Be brief** —
one line each. Do not fix anything; this is reconnaissance.

- **Inconsistencies**: two patterns for same concern (e.g. two HTTP clients, two test styles, mixed naming).
- **Architectural drift**: dependencies flowing wrong way, framework code in domain layers, god modules.
- **Stale or orphaned**: directories with no recent commits, dead config, TODO/FIXME clusters.
- **Risky areas**: missing tests, weak types, security-sensitive code without review, manual deploy steps.
- **Convention gaps**: behaviour exists but undocumented, or docs disagree with code.

If category has no findings, omit it. Do not pad.

### Step 4: Write or update description

Write result to `.agents/memory/active/project.md`. If the file already exists, update it where
necessary — preserve claims that are still accurate, fix or replace stale ones, add newly discovered
observations. If it does not exist, create it.

Follow template below. Adjust section titles to fit project, but keep section order: _purpose →
layout → architecture → lifecycle/workflows → conventions → rough edges → pointers_. This order
is what agent needs in roughly order it needs it.

Constraints on output:

- **Length**: target 80–150 lines. Hard cap 200. Density over completeness.
- **Voice**: technical, declarative, present tense. No marketing adjectives. No hedging.
- **Tables for layouts**: directory tables, file/role tables. Tables compress better than prose.
- **Cite paths**: every architectural claim points at file or folder.
- **No procedures**: do not document _how_ to install/build/test in detail — link to canonical doc instead.
- **Flag, do not solve**: _Rough edges_ section names problems without prescribing fixes.

### Step 5: Create or update preemptive skill loading manifest

Write or update `.agents/memory/active/preemptive-skill-loading-list.md` — a file that instructs future agent sessions
to preemptively load a concrete, explicit set of context skills based on this project's technologies and conventions.
This manifest eliminates the discovery cost at every session start.

If the file already exists: verify each listed skill's trigger signal is still present in the project. Remove
skills whose signals have disappeared (e.g., project dropped Docker), add skills for newly detected technologies.
If it does not exist, create it.

**How to infer the skill list**: Examine the technology signals gathered in Step 2 and reflected in `project.md`:

| Signal (from project exploration)                                                                      | Concrete skills to list                                                                       |
| ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Message bus / CQRS (Command/Query/Event handlers)                                                      | `devbot:software-development`                                                                 |
| Language / framework (dedicated rules + test + framework skills — see Language-specific signals below) | the language's dedicated skills                                                               |
| DDD / Hexagonal architecture (layered `src/`, ports/adapters)                                          | `devbot:explicit-architecture`, `devbot:architecture-rules`                                   |
| Git version control (`.git/` present)                                                                  | `devbot:git-conventional-commits`, `devbot:git-atomic-commits`, `git-workflow-and-versioning` |
| Makefile (`Makefile` with test/build targets)                                                          | `devbot:makefile`                                                                             |
| Tests (test directory present)                                                                         | `test-driven-development`, `devbot:make-tests`                                                |
| REST API (API routes/controllers)                                                                      | `devbot:rest-conventions`, `api-and-interface-design`                                         |
| Docker containers (`docker-compose.yml`, `Dockerfile*`)                                                | `devbot:dockerfile-authoring`                                                                 |
| Security-sensitive (auth, payments, PII handling)                                                      | `security-and-hardening`                                                                      |
| Frontend UI (React, Vue, Svelte, etc.)                                                                 | `frontend-ui-engineering`                                                                     |
| React specifically                                                                                     | `devbot:explicit-react`                                                                       |
| Svelte specifically                                                                                    | `devbot:explicit-svelte`                                                                      |
| Documentation (`docs/`, ADRs)                                                                          | `devbot:documentation-rules`                                                                  |
| CI/CD (`.github/workflows/`, `.gitlab-ci.yml`)                                                         | `ci-cd-and-automation`                                                                        |
| Kubernetes manifests (`k8s/`, `deploy/`)                                                               | `devbot:lint-k8s`                                                                             |
| Git hooks / automation (post-commit, pre-push scripts)                                                 | `git-workflow-and-versioning`                                                                 |
| Observability / logging tooling                                                                        | `observability-and-instrumentation`                                                           |

Language-specific signals are handled separately: for each detected language/framework, map to its dedicated skills (rules, test conventions, framework conventions). See the PHP/Laravel example below for the pattern.

**Process**:

1. Review the signals discovered during Step 2 and recorded in `project.md`.
2. Map each signal to its concrete skill name(s) using the table above. Only include skills whose
   trigger signal was actually observed — do not guess or pad.
3. Combine into a deduplicated, sorted list.
4. Select the **top 5–8 most impactful** skills (highest signal density). Avoid listing every
   possible skill; prioritize those the agent will use on every interaction.
5. Write the manifest.

**File format**:

```markdown
---
tags: [bootstrap, session, skills]
description: Context skills that must be preemptively loaded for correct agent behavior
---

## Preemptive Context Skill Loading

The agent must preemptively load the following context skills at the start of every session:

- `skill-name-1`
- `skill-name-2`
- `skill-name-3`

[One-sentence rationale per listed context skill — why loading it is necessary for this project.]
```

Example for a PHP/Laravel project:

```markdown
---
tags: [bootstrap, session, skills]
description: Context skills to preemptively load — PHP / Laravel project with message bus and hexagonal architecture
---

## Preemptive Context Skill Loading

The agent must preemptively load the following context skills at the start of every session:

- `devbot:software-development` — generic craft hub for code-quality, tests-first, and commit protocol; carries language-specific rules.
- `devbot:explicit-architecture` — DDD + Hexagonal layering; needed for correct file placement.
- `devbot:git-conventional-commits` — conventional commit message format (types, scope, ticket IDs); needed before any commit.
- `devbot:makefile` — all test/build commands run via `make` inside containers.
- `test-driven-development` — TDD workflow; tests must be written before implementation.
```

### Step 6: Optimize for agent consumption

Both deliverables (`project.md` and `preemptive-skill-loading-list.md`) are loaded into every future agent
session — token cost compounds. Run two passes on **both files**:

1. **Structure pass** — load the `devbot:optimize-instructions` context skill and apply its writing-rules checklist (economy,
   precision, non-redundant, scoped) to each file. Drop hedging, collapse prose into tables where
   possible, remove anything agent cannot act on.
2. **Skill list pass** — for `preemptive-skill-loading-list.md` specifically: verify every listed skill
   name matches an actual available skill. Remove any skill whose trigger signal was not observed in
   the project. The list must be concrete and justified.

### Step 7: Verify and report

1. Re-read both written files. For `project.md`: confirm every architectural claim maps to real path
   and no path mangled by compression pass. For `preemptive-skill-loading-list.md`: confirm every skill
   name is exact and maps to a real skill definition.
2. Run `wc -l` on `project.md`. If over 200 lines, compress further before reporting.
3. Report to caller using `devbot:agent-communication` `[FINISHED]` signal. Include: both file paths,
   `project.md` line count, skill count from `preemptive-skill-loading-list.md`, and 3-bullet recap
   (what project _is_, its dominant architectural pattern, top rough edge).

If exploration cannot proceed (repo unreadable, no source detected, write target inaccessible), follow
`devbot:exception-handling` and emit `[BLOCKED]` with specific cause and what needed to unblock.

## Template

> ---
>
> tags: [bootstrap, project] > description: What \<Project\> is, how repo laid out, key conventions and rough edges
> ---
>
> ## What this project is
>
> One paragraph: what project does, who it for, what makes distinctive. Name primary
> language(s), runtime, and any framework that shapes whole repo.
>
> ## Repository layout
>
> | Path     | Contents           |
> | -------- | ------------------ |
> | `<path>` | <one-line purpose> |
>
> Cover every top-level folder that matters. Group trivial folders into one row.
>
> ## Architecture
>
> Describe dominant pattern (layered, hexagonal, MVC, modular monolith, microservices, …) and actual
> module/component boundaries. Note direction of dependencies. If project follows documented
> pattern (e.g. DDD + Hexagonal), name it and point at canonical doc.
>
> Sub-bullets for: entry points, data stores, external services, key cross-cutting concerns (auth, logging,
> messaging).
>
> ## Lifecycle & workflows
>
> _(Optional — include only if project has non-obvious lifecycles like install/init/update, multi-stage
> deploy, or release pipelines worth knowing up front.)_
>
> If the project has a `Makefile`, list its key commands here (e.g. `make test`, `make up`, `make install`)
> and note that makefile commands are the **preferred** way to run any project command — over raw CLI or
> direct container commands.
>
> Brief, numbered. Link to canonical doc rather than reproducing.
>
> ## Runtime & deployment
>
> How the project runs and ships. Name the runtime (Docker, Kubernetes, serverless, bare metal) and the
> deployment mechanism (Helm charts, ArgoCD, Docker Compose, plain `docker run`, serverless deploy).
> Point at the deployment manifests/config (e.g. `k8s/`, `deploy/`, `helm/`, `.github/workflows/deploy.yml`).
> State whether merging to the default branch automatically deploys — if so, every merge is a production
> deploy (matters for migration/BC-break planning).
>
> ## CI/CD
>
> What CI system is used (GitHub Actions, GitLab CI, Jenkins) and what it looks like: which workflows/jobs
> exist, what each tests or does (lint, static analysis, unit/integration/e2e tests, build, deploy), and
> what manual actions (`workflow_dispatch`, retry, deploy buttons) are available.
>
> ## Critical conventions
>
> Bullet list. Each bullet is one rule contributor must know that is not obvious from code. Examples:
> dist vs runtime config files, gitignore patterns, symlinked paths, files-not-to-read, naming rules,
> whether the memory vault (`<devbot_dir>/memory/`) is committed to git or gitignored.
>
> ## Rough edges
>
> _(Omit if none found.)_
>
> Brief, factual. One bullet per observation. Examples:
>
> - Two test styles coexist: `tests/unit/` uses Pest, `tests/Feature/` uses PHPUnit.
> - `src/legacy/` has no tests and referenced by `src/api/v1/`.
> - `docs/architecture.md` describes v1 layout; code has since moved to v2 (see `src/v2/`).
>
> Do not propose fixes here.
>
> ## When to read docs vs code
>
> Pointers table: for question type → go to file/folder. Helps future agents skip exploration.

## Tools

Prefer these tools for efficient exploration:

- `devbot:graphify` — query codebase knowledge graph for architecture, core abstractions, and concept paths.
  Use first when available; see `devbot:graphify`.
- `repomix` — bulk-pack folder when needing broad context across many files in one area.
- `devbot:codebase-index` (`codebase_peek`, `codebase_search`) — locate concepts and definitions semantically.
- `glob` / `grep` — exact filename and pattern lookup.
- `ast-grep` — structural code search when prose grep ambiguous.

See `devbot:search-code` for choosing between them.

## MUST

- Write final description to `.agents/memory/active/project.md` and nowhere else.
- Write preemptive skill loading manifest to `.agents/memory/active/preemptive-skill-loading-list.md`.
- Update existing files where necessary — preserve accurate content, fix stale claims, add new observations.
  If files do not exist, create them.
- Cite real paths for every architectural claim; verify each path exists before writing.
- If the project has a `Makefile`, list its key commands in the description (Lifecycle & workflows) and note they are the preferred way to run project commands.
- Record the project's runtime, deployment mechanism, and CI system (with its jobs and actions) in the description.
- Record whether the memory vault is committed to git (from `commit_memory` config and `git ls-files <devbot_dir>/memory/`) so future agents know whether to commit memory files.
- List only concrete skill names in `preemptive-skill-loading-list.md` — never use categories like "all PHP skills".
- Run `devbot:optimize-instructions` pass before compression pass — order matters.
- Keep `project.md` at or under 200 lines; aim for 80–150 _after_ compression.
- End with `[FINISHED]` signal containing both file paths, line count, skill count, and 3-bullet recap.

## MUST NOT

- Write to any other location, or create supporting files in `bootstrap/`.
- Include install/build/test step-by-step instructions — link to canonical doc.
- Recommend fixes in _Rough edges_ section; flag only.
- Read or describe files marked `no-vcs` or excluded by `ignore.md`.
- Pad with marketing language, aspirations, or generic best-practice advice.
- List skills not observed in the project — every skill must have a trigger signal found during exploration.
- Use generic categories (e.g., "all PHP skills") instead of concrete skill names.
