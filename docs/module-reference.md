---
layout: page
title: Module Reference
description: DevBot modules — self-contained capability units.
nav_section: docs
---

## Module anatomy

Every module follows the same structure under `src/agentic/<name>/`. **All entries are optional** — a module includes only what it needs:

```
<module>/
  agents/               Agent profiles
  commands/             Repeatable instruction sets invocable via agent input
  skills/               Agent-readable skill instructions (SKILL.md per skill)
  hooks.json            Declarative hook manifest (harness-agnostic)
  hooks/git/            Git hooks (optional)
  tools/                Executable tools (`.sh` CLI wrappers, `.py`/`.ts` helpers)
    opencode/           TS thin wrapper for the OpenCode tool palette
    claudecode/         MCP server script (e.g. graphify's mcp-server.js)
  memory/               Bootstrap files symlinked into `.agents/memory/` (external modules)
  tests/                BATS test suite
  install.sh            Idempotent OS dependency installer
  update.sh             Dependency update script
  init.sh               Per-project initialization
  up.sh                 Post-docker startup script
  down.sh               Pre-teardown script
  pre.sh                Prerequisites check
  reset.sh              Per-project state reset
  start.sh              Launch the harness binary (harnesses only)
  functions.sh          Thin wrapper sourcing `src/_shared/functions.sh`
  mcp.opencode.json     OpenCode MCP server definition for auto-registration
  mcp.claudecode.json   Claude Code MCP server definition
  external-modules.json External module dependencies declared by this module
```

### Lifecycle scripts

**install.sh**: Idempotent — can be run multiple times safely. Installs OS-level dependencies. Run automatically by `bin/install.sh` which loops over all modules.

**update.sh**: Updates dependencies to latest compatible versions. Run by `bin/update.sh`.

**pre.sh**: Checks module prerequisites (Python 3, API reachability, etc.). Run automatically by `bin/install.sh` and `bin/update.sh`. Must be idempotent and non-destructive. Warnings (not errors) for optional deps.

**init.sh**: Per-project initialization. Run by `bin/init.sh`.

**up.sh**: Post-docker startup script. Use for pulling models, waiting for services, seeding data.

**down.sh**: Pre-teardown script. Run by `bin/down.sh` before docker services stop.

**reset.sh**: Resets per-project state. Run by `bin/reinit.sh` (`devbot reinit`) before re-running init.

**start.sh** (harnesses only): Launches the harness binary (`claude` / `opencode`) without forcing an agent — the session agent comes from the project's default (`opencode.jsonc` `default_agent` / `.claude/settings.json` `agent`), created with DevBot by default during init and only asked about when an existing config chose a different agent. Run by `devbot` (`cmd_harness` in `bin/devbot`) to start the configured harness; not part of the generic lifecycle loops. Accepts an optional project directory as `$1` and forwards remaining args to the harness binary. Before launching it rotates the previous session's `.agents/logs/*.log` files to `.agents/logs/rotated/<date>-<name>-<NNN>.log`, then runs the harness as a child (not `exec`); on exit it scans the fresh logs for error-level lines, alerts the user, and exits with the harness's exit code.

### Hooks

Hooks are declared in a per-module `hooks.json` manifest (harness-agnostic) and wired by one generic adapter per harness — `on-hooks.ts` (OpenCode) and `on-hooks.py` (Claude Code). Business logic lives in `tools/`; the manifest's `run` command references it via `{module}/tools/…`. See [Hooks](/hooks) for the schema, the six semantic events, and the hand-written `devbot:auto-recover` exception.

### Tools

When a tool is present, it must:

- Contain a bash script so the user can trigger it directly
- Default output format: Markdown
- Agent tools (TS/JS wrappers around the bash script) default to JSON to save tokens

`.ts` files are the authoritative source of truth — business logic lives there. `.sh` files are thin CLI wrappers that delegate to `.ts` via `bun run`. They never contain business logic.

### Testing

Tests use the **bats** framework (Bash Automated Testing System). Install via `npm install -g bats bats-assert bats-support`. `make test` auto-installs bats if missing.

Test fixtures go in `<module>/tests/fixtures/` and should be minimal — create what is needed for the test, clean up after.

---

## Internal modules

Located at `src/agentic/<name>/`. Each provides agent skills, tools, hooks, agents, or MCP servers.

| Module              | S   | T   | A   | H   | MCP | Description                                                                                                                                                                                                                                                                              |
| ------------------- | --- | --- | --- | --- | --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| agent-communication | 1   | 1   | —   | 2   | —   | Structured inter-agent protocol — validates terminal status markers in messages                                                                                                                                                                                                          |
| architecture        | 5   | —   | —   | —   | —   | Architecture governance: design rules, DDD+Hex+CQRS layers, codebase audits, test suite audits, ADRs                                                                                                                                                                                     |
| auto-recover        | 2   | —   | —   | 3   | —   | Automatic recovery from transient provider errors + structured exception handling                                                                                                                                                                                                        |
| chrome-devtools     | —   | —   | —   | —   | ✓   | Browser DevTools MCP — inspect DOM, console, network, performance traces                                                                                                                                                                                                                 |
| codebase-index      | 1   | —   | —   | —   | ✓   | Semantic code search via Ollama embeddings — find code by meaning, not keywords                                                                                                                                                                                                          |
| context7            | —   | —   | —   | —   | ✓   | Official documentation retrieval for any library/framework                                                                                                                                                                                                                               |
| dev                 | 5   | —   | —   | —   | —   | Dev conventions: software-development (craft hub), address-review, rest-conventions, makefile, make-tests                                                                                                                                                                                |
| devbot              | —   | —   | 3   | —   | —   | Pair programming partner agent + Expert and Designer subagents — works alongside human incrementally, never autonomously                                                                                                                                                                 |
| devteam             | 6   | —   | 9   | —   | —   | Multi-agent team: TeamLead orchestrator + 8 subagents (PO, Architect, Critic, Developer, Tester, Reviewer, Scout, Security). 6 workflow skills: devbot:make-plan, devbot:review-plan, devbot:implement-plan, devbot:implement-story, devbot:review-implementation, devbot:summarize-plan |
| docker              | 1   | —   | —   | —   | —   | Dockerfile authoring — battle-tested patterns for production-grade container builds                                                                                                                                                                                                      |
| docs                | 4   | 2   | —   | —   | —   | Documentation — use-case maps from PHP code, interactive app-map editor, gh-docs-website, documentation-rules                                                                                                                                                                            |
| explore             | 3   | —   | —   | —   | —   | Codebase exploration: devbot:gather-context (session priming), devbot:create-project-report, devbot:search-code                                                                                                                                                                          |
| format-json         | 1   | 2   | —   | 2   | —   | Auto-formats .json/.jsonc files via prettier on save                                                                                                                                                                                                                                     |
| format-md           | 1   | 2   | —   | 2   | —   | Auto-formats .md files via prettier on save — aligns table columns, normalizes spacing                                                                                                                                                                                                   |
| format-yml          | 1   | 2   | —   | 2   | —   | Auto-formats .yml/.yaml files via prettier on save                                                                                                                                                                                                                                       |
| git                 | 5   | 2   | —   | —   | —   | Git workflow skills (atomic/ conventional/ fixup commits, advanced history surgery, git-report) + git-report tool                                                                                                                                                                        |
| github              | —   | —   | —   | —   | —   | GitHub integration: gh-review command + GitHub CLI (gh) install/update lifecycle scripts                                                                                                                                                                                                 |
| graphify            | 1   | 4   | —   | 5   | ✓   | Codebase knowledge graph — build, query path/explain, community detection, god nodes                                                                                                                                                                                                     |
| guards              | 1   | —   | —   | 2   | —   | Evaluates bash commands against configurable guard rules before execution                                                                                                                                                                                                                |
| jetbrains           | —   | —   | —   | —   | ✓   | JetBrains IDE integration — code analysis, inspections, debugging, database tools                                                                                                                                                                                                        |
| k8s                 | 1   | 1   | —   | 2   | —   | Kubernetes manifest linting — kubeconform (schema) + kube-linter (best practices)                                                                                                                                                                                                        |
| memory              | 5   | 3   | —   | 7   | —   | Knowledge vault: devbot:search-memory, devbot:remember-session, devbot:memory-management, devbot:prune-memories, devbot:thinking + reindex-memories/search-memories tools                                                                                                                |
| playwright          | —   | —   | —   | —   | ✓   | Browser automation via Playwright MCP — drive real browser sessions for E2E testing                                                                                                                                                                                                      |
| qmd                 | 1   | 1   | —   | —   | ✓   | Semantic search over markdown vaults (BM25 + vector + hybrid + LLM reranking)                                                                                                                                                                                                            |
| react               | 1   | —   | —   | —   | ✓   | React 18+ and Next.js development conventions + next-devtools MCP                                                                                                                                                                                                                        |
| repomix             | —   | —   | —   | —   | —   | Directory packing into single structured file for full-context analysis                                                                                                                                                                                                                  |
| security            | 1   | —   | —   | —   | —   | Security auditing: STRIDE threat modelling, OWASP Top 10, PHP vulnerability assessment                                                                                                                                                                                                   |
| self-improvement    | 13  | —   | —   | —   | —   | Meta-optimization: create-skill/agent/module, create-opencode/claudecode hook/tool, make-retrospective, improve-planning/reviewer/implementation, optimize-instructions                                                                                                                  |
| signoz              | —   | —   | —   | —   | ✓   | SigNoz observability platform — dashboards, alerts, queries, investigation                                                                                                                                                                                                               |
| svelte              | 1   | —   | —   | —   | ✓   | Svelte development conventions + Svelte MCP                                                                                                                                                                                                                                              |
| tools-mcp           | 1   | —   | —   | —   | ✓   | MCP server exposing devbot custom tools to agents — each tool self-describes via mcp-meta subcommand                                                                                                                                                                                     |
| tree                | 1   | 1   | —   | —   | —   | Directory tree inspection — shows subfolders and files in markdown, plain text, or JSON                                                                                                                                                                                                  |
| websearch           | —   | —   | —   | —   | ✓   | Web search via Exa API — current information retrieval beyond LLM knowledge cutoff                                                                                                                                                                                                       |

**S** = Skills, **T** = Tool scripts, **A** = Agents, **H** = Hook scripts (opencode `.ts` + claudecode `.sh`), **MCP** = MCP server

**Module count**: 33 modules.

---

## Tools modules

Located at `src/tools/<name>/`. Infrastructure services — Docker Compose, CLI lifecycle, project initialization.

| Tool             | Description                                                             |
| ---------------- | ----------------------------------------------------------------------- |
| devbot           | CLI entry point — install, init, update, up, down, tool, module, models |
| external-modules | Module lifecycle CLI: `devbot module add/remove/list/sync`              |
| litellm          | LiteLLM proxy for local LLM access (disabled by default)                |
| ollama           | Local LLM inference server (port 18434), model management               |

**Disabled by default**: `litellm` is skipped during install/update/init unless overridden in `.devbot.global.jsonc`.

---

## External modules

External modules bring third-party agent artifacts (skills, agents, commands, memory bootstrap files) into projects. Each module is either **git-sourced** (a `url`, shallow-cloned into `vendor/<org>/<repo>`) or **path-sourced** (a local directory via `path`, wired in place — never cloned). Module names are **namespaced identities**: `<org>/<repo>` for git modules, `local/<folder>` for local ones. Their artifacts are symlinked into each project's devbot dir — nested as `.agents/<type>/<org>/<repo>/<path-basename>` (the `<org>/<repo>` level is a container dir holding one leaf symlink per declared path, see [Configuration format](#configuration-format)) — by the module's `init.sh`, which runs automatically as part of `devbot init`. External modules follow the same anatomy as internal modules and may themselves declare further external modules (see [Transitive declarations](#transitive-declarations)).

### Registered modules

Declared by dev-bot's own modules (see `src/tools/external-modules/external-modules.json`). Additional modules can be registered per installation under `external_modules` (see [Configuration format](#configuration-format) below):

| Name                    | Source                             | Wires               |
| ----------------------- | ---------------------------------- | ------------------- |
| addyosmani/agent-skills | github.com/addyosmani/agent-skills | 4 agents, 24 skills |
| mattpocock/skills       | github.com/mattpocock/skills       | skills              |

### Module CLI

Manage external module repos — clone, register, and wire into projects via `devbot module`.

```
devbot module add <git-url|local-path> [options]
devbot module remove <name> [--path=<rel>]
devbot module list
devbot module sync
```

#### `add <git-url|local-path>`

Register an external module from a git URL or a local directory.

| Option              | Default      | Description                                |
| ------------------- | ------------ | ------------------------------------------ |
| `--name=<name>`     | repo name    | Override the module name                   |
| `--skills=<path>`   | `./skills`   | Path to skills directory within the module |
| `--agents=<path>`   | `./agents`   | Path to agents directory                   |
| `--commands=<path>` | `./commands` | Path to commands directory                 |
| `--plugins=<path>`  | `./plugins`  | Path to plugins directory                  |

When `<url-or-path>` is an existing directory, it is registered as a **local module** under `local/<folder>` (see [Configuration format](#configuration-format) below) — it is never cloned into `vendor/`, and its artifacts are wired straight from that directory. Otherwise it is treated as a git URL (a `url` entry) and registered under `<org>/<repo>`, cloned into `vendor/` on install.

**Examples:**

```bash
devbot module add https://github.com/org/my-skills.git      # registers "org/my-skills"
devbot module add /path/to/my/module                        # registers "local/my-module"
devbot module add /path/to/other --name=custom              # registers "local/custom"
devbot module add https://github.com/org/repo.git --skills=./my-skills --agents=./my-agents
```

`--name` applies to **local** modules only (the folder part under `local/`); git module names are derived from the url. After registration, run `devbot init <project>` to wire the module's artifacts into `<project>/.agents/<type>/<name>`.

#### `remove <name>`

Unregister a module by name. Removes symlinks from all projects and deletes the config entry. With `--path=<rel>` only that one directory path is removed — the config entry keeps its remaining paths, and the matching `.agents` leaf and storage leaf are unwired. Removing the last path removes the whole entry:

```bash
devbot module remove my-module
devbot module remove org/my-repo --path=skills/react   # drop one collection
```

If the entry is declared by a module (`_declared_by`), the next `devbot install` re-adds a removed path from that module's declaration — per-path removal is authoritative until the declaring module changes.

#### `list`

Show all registered modules with their clone/link status.

```
✔  addyosmani/agent-skills  [git]    (vendor/addyosmani/agent-skills)
✔  local/my-module          [local]  (/path/to/my/module)
✖  org/other                [git]    (vendor/org/other)
```

#### `sync`

Alias for `init` (kept for backward compatibility): wires the configured modules into the given project's `.agents/` directory.

```bash
devbot module sync <project>
```

#### Configuration format

External modules are defined in `.devbot.global.jsonc` under the `"external_modules"` key. Each entry maps a **namespaced name** to a source and optional paths. The source is exactly one of `url` (git-sourced) or `path` (local directory); the name is `<org>/<repo>` (derived from the url) or `local/<folder>`:

```jsonc
"external_modules": {
  "addyosmani/agent-skills": {
    "url": "https://github.com/addyosmani/agent-skills.git",
    "paths": {
      "agents": "agents",       // directory symlink — all files linked
      "skills": "skills",       // directory symlink — all files linked
      "memory": {
        "external/repo/path/instructions.md": "link/path/instructions.md"
        // file-level symlink — individual file wired at exact path
      }
    }
  },
  "local/my-local-skills": {
    "path": "/absolute/path/to/local/folder",
    "paths": {
      "skills": "skills"
    }
  }
}
```

**Source key semantics:**

- **`url`** — git-sourced. The repo is shallow-cloned into `vendor/<org>/<repo>` on `devbot install` and artifacts are wired from the clone.
- **`path`** — local directory. Nothing is cloned or copied into `vendor/`; the directory is verified to exist on install and artifacts are symlinked straight from it. The local source is **never modified** — in particular the post-clone README cleanup only ever applies to clones, never to a local source.
- **Both set** — `path` takes precedence and no clone happens. This lets you point a declared (git-sourced) module at a local checkout while you iterate on it.
- **Neither set** — the entry is skipped with a warning.

**Provenance** (recorded by the tooling, not hand-edited): declaration merges record `"_declared_by": [<module>, ...]` (the union of modules that declare the entry); CLI registrations record `"_user_added": true`. `devbot install` prunes an entry only when it is not user-added and **every** declarer is disabled or gone — so removing a parent module chains its transitive children away, while an entry kept alive by one remaining declarer (or by the user) survives.

`external_modules` entries are **global to a dev-bot installation** (`.devbot.global.jsonc` is gitignored), so a `path` pointing at a machine-specific directory is safe to add per machine. Every entry that survives pruning — declared or user-added, git or local — is wired on the next `devbot init`.

**`paths` key semantics:**

- **String value** (`"skills": "skills"`) — the entire directory from the module is symlinked into the `.agents/<type>/<org>/<repo>/` container with the path's basename as leaf (legacy form, still valid)
- **Array value** (`"skills": ["skills/react", "skills/nextjs-react-typescript"]`) — **additive paths**: one repo shipping several collections. Each element is wired under the same container as a leaf symlink named by its basename (`.agents/skills/mindrally/skills/react`, `…/nextjs-react-typescript`). Same-basename elements within one type are refused at wire time (first wins). String and array are both accepted; array is the canonical form
- **Object value** (`"memory": { "source": "dest" }`) — each file is symlinked individually at its exact destination path. Used for `memory/` bootstrap files that must sit alongside internal bootstrap files without an extra nesting level. Object values are never array elements (arrays apply to directory types only)
- **Missing paths** — if a path key is omitted, that module type is not wired

**One entry per repo**: a declaration whose git url derives to an `org/repo` already present under a different key is refused by the merge tool (insert/update) with an error naming the canonical key — local `path` entries are unaffected.

**Storage layout** (after wiring):

| Path                                              | Purpose                                                                                                                      |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `<devbot-root>/.devbot.global.jsonc`              | Module registry (under `external_modules` key)                                                                               |
| `<devbot-root>/vendor/<org>/<repo>/`              | Cloned repository (git-sourced modules only)                                                                                 |
| `<local-path>/`                                   | Local source directory (path-sourced modules — never copied)                                                                 |
| `storage/external-agentic-modules/<org>__<repo>/` | Storage mirror (dir/file symlinks + lifecycle scripts); `/` in config names sanitized to `__` so the dir is one path segment |
| `<project>/.agents/<type>/<org>/<repo>/`          | Container dir in each project's devbot dir — one leaf symlink per declared path, named by the path's basename                |

**Transitive declarations**

External modules are a dependency graph. Any external module root (a `vendor/` clone or a local `path` directory) may carry its own `external-modules.json`; `devbot install` resolves the graph breadth-first, merging each module's declarations (owned by that module's name) and cloning/wiring the newly declared modules until nothing new appears. Cycles are cut by the visited set. Declarations are `url`-only — a tracked `external-modules.json` never carries a machine-specific local `path`.

#### How it works

1. Register the module in `.devbot.global.jsonc` under `external_modules` — via `devbot module add <url|dir>` (names are derived: `<org>/<repo>` or `local/<folder>`) or by editing the config directly (see [Configuration format](#configuration-format))
2. `devbot install` — git-sourced modules are shallow-cloned/updated into `vendor/<org>/<repo>`; path-sourced modules are only verified to exist (their READMEs are never touched). Each module's own `external-modules.json` is merged and its transitive modules processed to closure
3. `devbot install` prunes entries whose declarers are all disabled/gone (user-added entries survive) and vendor clones no longer referenced
4. `devbot init <project>` — the module's `init.sh` symlinks each configured artifact into `<project>/.agents/<type>/<org>/<repo>/<path-basename>` (a container dir per entry holding one leaf per path; legacy repo-leaf symlinks are converted on re-init) and mirrors it into `storage/external-agentic-modules/<sanitized-name>/`
5. Memory bootstrap files declared under `paths.memory` are linked into `<project>/.agents/memory/`
6. `devbot module remove <name>` unwires the `.agents` containers and legacy `.opencode` links and deletes the config entry; `remove <name> --path=<rel>` drops one path; storage dirs no longer present in the config are pruned on the next init
