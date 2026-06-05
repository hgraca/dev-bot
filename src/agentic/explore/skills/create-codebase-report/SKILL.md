---
name: create-codebase-report
description: "Explores the entire project and produces a technical description at .agents/memory/active/project.md covering structure, purpose, architecture, conventions, and known inconsistencies, plus a preemptive-skill-loading list. Use this skill whenever onboarding to a new project, when the description is missing or stale, when the user says 'explore the project', 'describe the project', 'map the codebase', 'document the architecture', or invokes /create-codebase-report — and when starting work on an unfamiliar repo before planning."
---

# Skill: Explore Project

Produce concise, technical project description any agent or human can load at session start to understand
_what this project is_, _how laid out_, and _where rough edges are_. Output: two files —
`.agents/memory/active/project.md` (project map) and `.agents/memory/active/preemptive-skill-loading.md`
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

Read `.agents/memory/active/project.md` and `.agents/memory/active/preemptive-skill-loading.md`
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
   If `graphify` unavailable or graph empty/stale, skip and proceed with file-based survey.
   See `graphify`.
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
7. **CI/CD and tooling**: `.github/workflows/`, `.gitlab-ci.yml`, `Dockerfile*`, `Makefile` targets, lint/format config.

Prefer broad coverage over depth. If folder gitignored or marked `no-vcs`, skip (see `ignore.md`).

**`.ai/` directory**: holds agent-only artefacts (memory vault, planning issue folders,
thinking/scratch, project rules). **Gitignored by convention** — nothing under `.ai/` committed to
project repository. Treat as local working state for agents, not as project source. When writing
description, mention `.ai/` under _Repository layout_ (one row, noting "agent working state, gitignored")
and under _Critical conventions_ (rule that `.ai/` contents never committed). Do not enumerate its
sub-structure — that belongs to `memory-management`.

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

Write or update `.agents/memory/active/preemptive-skill-loading.md` — a file that instructs future agent sessions
to preemptively load a concrete, explicit set of skills based on this project's technologies and conventions.
This manifest eliminates the discovery cost at every session start.

If the file already exists: verify each listed skill's trigger signal is still present in the project. Remove
skills whose signals have disappeared (e.g., project dropped Docker), add skills for newly detected technologies.
If it does not exist, create it.

**How to infer the skill list**: Examine the technology signals gathered in Step 2 and reflected in `project.md`:

| Signal (from project exploration)                                      | Concrete skills to list                                                         |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| PHP codebase (`composer.json`, `.php` files)                           | `php-rules`, `phpunit`                                                          |
| Laravel framework (`laravel/framework` in composer.json, `artisan`)    | `laravel`                                                                       |
| Message bus / CQRS (`get-e/message-bus`, Command/Query/Event handlers) | `message-bus`, `make-use-case`                                                  |
| DDD / Hexagonal architecture (layered `src/`, ports/adapters)          | `explicit-architecture`, `architecture-rules`                                   |
| Git version control (`.git/` present)                                  | `git-conventional-commits`, `git-atomic-commits`, `git-workflow-and-versioning` |
| Makefile (`Makefile` with test/build targets)                          | `makefile`                                                                      |
| Tests (`tests/`, `phpunit.xml`, `pest`)                                | `test-driven-development`, `make-tests`                                         |
| REST API (`routes/api.php`, API controllers)                           | `rest-conventions`, `api-and-interface-design`                                  |
| Docker containers (`docker-compose.yml`, `Dockerfile*`)                | `dockerfile-authoring`                                                          |
| Security-sensitive (auth, payments, PII handling)                      | `security-and-hardening`                                                        |
| Frontend UI (React, Vue, Svelte, Blade, etc.)                          | `frontend-ui-engineering`                                                       |
| React specifically                                                     | `explicit-react`                                                                |
| Svelte specifically                                                    | `explicit-svelte`                                                               |
| Documentation (`docs/`, ADRs)                                          | `documentation-rules`                                                           |
| CI/CD (`.github/workflows/`, `.gitlab-ci.yml`)                         | `ci-cd-and-automation`                                                          |
| Kubernetes manifests (`k8s/`, `deploy/`)                               | `lint-k8s`                                                                      |
| Git hooks / automation (post-commit, pre-push scripts)                 | `git-workflow-and-versioning`                                                   |
| Observability / logging tooling                                        | `observability-and-instrumentation`                                             |

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
description: Skills that must be preemptively loaded for correct agent behavior
---

## Preemptive Skill Loading

The agent must preemptively load the following skills at the start of every session:

- `skill-name-1`
- `skill-name-2`
- `skill-name-3`

[One-sentence rationale per listed skill — why loading it is necessary for this project.]
```

Example for a PHP/Laravel project:

```markdown
---
tags: [bootstrap, session, skills]
description: Skills to preemptively load — PHP / Laravel project with message bus and hexagonal architecture
---

## Preemptive Skill Loading

The agent must preemptively load the following skills at the start of every session:

- `php-rules` — all production code is PHP; enforces strict typing, constructor promotion, and PHPDoc conventions.
- `laravel` — Laravel 10 framework conventions for Eloquent, controllers, validation, and Artisan commands.
- `message-bus` — CQRS command/event/query handler patterns; needed for any use case work.
- `explicit-architecture` — DDD + Hexagonal layering; needed for correct file placement.
- `git-conventional-commits` — conventional commit message format (types, scope, ticket IDs); needed before any commit.
- `makefile` — all test/build commands run via `make` inside containers.
- `phpunit` — PHPUnit conventions; needed before writing or running any test.
- `test-driven-development` — TDD workflow; tests must be written before implementation.
```

### Step 6: Optimize for agent consumption

Both deliverables (`project.md` and `preemptive-skill-loading.md`) are loaded into every future agent
session — token cost compounds. Run two passes on **both files**:

1. **Structure pass** — load `optimize-instructions` and apply its writing-rules checklist (economy,
   precision, non-redundant, scoped) to each file. Drop hedging, collapse prose into tables where
   possible, remove anything agent cannot act on.
2. **Skill list pass** — for `preemptive-skill-loading.md` specifically: verify every listed skill
   name matches an actual available skill. Remove any skill whose trigger signal was not observed in
   the project. The list must be concrete and justified.

### Step 7: Verify and report

1. Re-read both written files. For `project.md`: confirm every architectural claim maps to real path
   and no path mangled by compression pass. For `preemptive-skill-loading.md`: confirm every skill
   name is exact and maps to a real skill definition.
2. Run `wc -l` on `project.md`. If over 200 lines, compress further before reporting.
3. Report to caller using `agent-communication` `[FINISHED]` signal. Include: both file paths,
   `project.md` line count, skill count from `preemptive-skill-loading.md`, and 3-bullet recap
   (what project _is_, its dominant architectural pattern, top rough edge).

If exploration cannot proceed (repo unreadable, no source detected, write target inaccessible), follow
`exception-handling` and emit `[BLOCKED]` with specific cause and what needed to unblock.

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
> Brief, numbered. Link to canonical doc rather than reproducing.
>
> ## Critical conventions
>
> Bullet list. Each bullet is one rule contributor must know that is not obvious from code. Examples:
> dist vs runtime config files, gitignore patterns, symlinked paths, files-not-to-read, naming rules.
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

- `graphify` — query codebase knowledge graph for architecture, core abstractions, and concept paths.
  Use first when available; see `graphify`.
- `repomix` — bulk-pack folder when needing broad context across many files in one area.
- `codebase-index` (`codebase_peek`, `codebase_search`) — locate concepts and definitions semantically.
- `glob` / `grep` — exact filename and pattern lookup.
- `ast-grep` — structural code search when prose grep ambiguous.

See `search-code` for choosing between them.

## MUST

- Write final description to `.agents/memory/active/project.md` and nowhere else.
- Write preemptive skill loading manifest to `.agents/memory/active/preemptive-skill-loading.md`.
- Update existing files where necessary — preserve accurate content, fix stale claims, add new observations.
  If files do not exist, create them.
- Cite real paths for every architectural claim; verify each path exists before writing.
- List only concrete skill names in `preemptive-skill-loading.md` — never use categories like "all PHP skills".
- Run `optimize-instructions` pass before compression pass — order matters.
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
