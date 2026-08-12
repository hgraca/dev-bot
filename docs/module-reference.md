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
  hooks/                Event-driven hooks
    opencode/           OpenCode plugin (TS)
    claudecode/         Claude Code hook (bash)
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

### Hooks

OpenCode hooks are TypeScript plugins under `hooks/opencode/`. During install, `install.sh` symlinks the TS file into `.opencode/plugins/devbot/` so OpenCode discovers it. The symlink uses a relative path so it survives repo moves.

Claude Code hooks are bash scripts under `hooks/claudecode/`. They must be registered manually in `~/.claude/settings.json` — each script's header documents the config.

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

| Module              | S   | T   | A   | H   | MCP | Description                                                                                                                                                                                                                                    |
| ------------------- | --- | --- | --- | --- | --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| agent-communication | 1   | 1   | —   | 2   | —   | Structured inter-agent protocol — validates terminal status markers in messages                                                                                                                                                                |
| architecture        | 5   | —   | —   | —   | —   | Architecture governance: design rules, DDD+Hex+CQRS layers, codebase audits, test suite audits, ADRs                                                                                                                                           |
| auto-recover        | 2   | —   | —   | 3   | —   | Automatic recovery from transient provider errors + structured exception handling                                                                                                                                                              |
| aws                 | 1   | 1   | —   | —   | ✓   | AWS MCP proxy — local server exposing AWS APIs to agents (disabled by default)                                                                                                                                                                 |
| chrome-devtools     | —   | —   | —   | —   | ✓   | Browser DevTools MCP — inspect DOM, console, network, performance traces                                                                                                                                                                       |
| codebase-index      | 1   | —   | —   | —   | ✓   | Semantic code search via Ollama embeddings — find code by meaning, not keywords                                                                                                                                                                |
| context7            | —   | —   | —   | —   | ✓   | Official documentation retrieval for any library/framework                                                                                                                                                                                     |
| dev                 | 10  | —   | —   | —   | —   | Dev conventions: php-rules, laravel, phpunit, message-bus, rest-conventions, documentation-rules, makefile, gh-review, make-tests, make-use-case                                                                                               |
| devbot              | —   | —   | 3   | —   | —   | Pair programming partner agent + Expert and Designer subagents — works alongside human incrementally, never autonomously                                                                                                                       |
| devteam             | 6   | —   | 9   | —   | —   | Multi-agent team: TeamLead orchestrator + 8 subagents (PO, Architect, Critic, Developer, Tester, Reviewer, Scout, Security). 6 workflow skills: make-plan, review-plan, implement-plan, implement-story, review-implementation, summarize-plan |
| docker              | 1   | —   | —   | —   | —   | Dockerfile authoring — battle-tested patterns for production-grade container builds                                                                                                                                                            |
| docs                | 3   | 2   | —   | —   | —   | Architecture documentation — use-case maps from PHP code, interactive app-map editor, gh-docs-website                                                                                                                                          |
| explore             | 3   | —   | —   | —   | —   | Codebase exploration: gather-context (session priming), create-codebase-report, search-code                                                                                                                                                    |
| format-json         | 1   | 2   | —   | 2   | —   | Auto-formats .json/.jsonc files via prettier on save                                                                                                                                                                                           |
| format-md           | 1   | 2   | —   | 2   | —   | Auto-formats .md files via prettier on save — aligns table columns, normalizes spacing                                                                                                                                                         |
| format-yml          | 1   | 2   | —   | 2   | —   | Auto-formats .yml/.yaml files via prettier on save                                                                                                                                                                                             |
| git                 | 5   | 2   | —   | —   | —   | Git workflow skills (atomic/ conventional/ fixup commits, advanced history surgery, git-report) + git-report tool                                                                                                                              |
| graphify            | 1   | 4   | —   | 5   | ✓   | Codebase knowledge graph — build, query path/explain, community detection, god nodes                                                                                                                                                           |
| guards              | 1   | —   | —   | 2   | —   | Evaluates bash commands against configurable guard rules before execution                                                                                                                                                                      |
| jetbrains           | —   | —   | —   | —   | ✓   | JetBrains IDE integration — code analysis, inspections, debugging, database tools                                                                                                                                                              |
| k8s                 | 1   | 1   | —   | 2   | —   | Kubernetes manifest linting — kubeconform (schema) + kube-linter (best practices)                                                                                                                                                              |
| memory              | 5   | 3   | —   | 7   | —   | Knowledge vault: search-memory, remember-session, memory-management, prune-memories, thinking + reindex-memories/search-memories tools                                                                                                         |
| playwright          | —   | —   | —   | —   | ✓   | Browser automation via Playwright MCP — drive real browser sessions for E2E testing                                                                                                                                                            |
| qmd                 | 1   | 1   | —   | —   | ✓   | Semantic search over markdown vaults (BM25 + vector + hybrid + LLM reranking)                                                                                                                                                                  |
| react               | 1   | —   | —   | —   | ✓   | React 18+ and Next.js development conventions + next-devtools MCP                                                                                                                                                                              |
| repomix             | —   | —   | —   | —   | —   | Directory packing into single structured file for full-context analysis                                                                                                                                                                        |
| security            | 1   | —   | —   | —   | —   | Security auditing: STRIDE threat modelling, OWASP Top 10, PHP vulnerability assessment                                                                                                                                                         |
| self-improvement    | 13  | —   | —   | —   | —   | Meta-optimization: create-skill/agent/module, create-opencode/claudecode hook/tool, make-retrospective, improve-planning/reviewer/implementation, optimize-instructions                                                                        |
| signoz              | —   | —   | —   | —   | ✓   | SigNoz observability platform — dashboards, alerts, queries, investigation                                                                                                                                                                     |
| svelte              | 1   | —   | —   | —   | ✓   | Svelte development conventions + Svelte MCP                                                                                                                                                                                                    |
| tools-mcp           | 1   | —   | —   | —   | ✓   | MCP server exposing devbot custom tools to agents — each tool self-describes via mcp-meta subcommand                                                                                                                                           |
| tree                | 1   | 1   | —   | —   | —   | Directory tree inspection — shows subfolders and files in markdown, plain text, or JSON                                                                                                                                                        |
| websearch           | —   | —   | —   | —   | ✓   | Web search via Exa API — current information retrieval beyond LLM knowledge cutoff                                                                                                                                                             |

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

Third-party modules registered via `devbot module add` and wired into projects via symlinks. Cloned into `vendor/` with symlinks in `.opencode/<type>/<name>/`. External modules follow the same anatomy as internal modules — they can provide agents, skills, commands, hooks, tools, and memory bootstrap files. The runtime treats them identically; the only difference is where they live on disk (`vendor/` vs `src/agentic/`).

### Registered modules

| Name                           | Source                                 | Wires               |
| ------------------------------ | -------------------------------------- | ------------------- |
| addyosmani                     | github.com/addyosmani/agent-skills     | 4 agents, 24 skills |
| mindrally-svelte               | github.com/mindrally/skills            | skills              |
| sveltekit-structure            | github.com/spences10/svelte-skills-kit | skills              |
| svelte5-best-practices         | github.com/ejirocodes/agent-skills     | skills              |
| mindrally-react                | github.com/mindrally/skills            | skills              |
| mindrally-nextjs               | github.com/mindrally/skills            | skills              |
| mindrally-react-best-practices | github.com/mindrally/skills            | skills              |
| mattpocock-grilling            | github.com/mattpocock/skills           | skills              |
| agent-toolkit-for-aws          | github.com/aws/agent-toolkit-for-aws   | skills              |

### Module CLI

Manage external module repos — clone, register, and wire into projects via `devbot module`.

```
devbot module add <git-url|local-path> [options]
devbot module remove <name>
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

When `<url-or-path>` is an existing directory, it's treated as a **local module** (no cloning, symlinked into `vendor/`). Otherwise it's treated as a git URL and cloned into `vendor/`.

**Examples:**

```bash
devbot module add https://github.com/org/my-skills.git
devbot module add https://github.com/org/repo.git --name=custom-name
devbot module add /path/to/my/module
devbot module add https://github.com/org/repo.git --skills=./my-skills --agents=./my-agents
```

After registration, the module is automatically wired into all discovered projects via symlinks in `.opencode/<type>/<name>/`.

#### `remove <name>`

Unregister a module by name. Removes symlinks from all projects and deletes the config entry.

```bash
devbot module remove my-module
```

#### `list`

Show all registered modules with their clone/link status.

```
✔  addyosmani  [git]    (vendor/github.com/addyosmani/agent-skills)
✔  my-module   [local]  (/path/to/my/module)
✖  other       [git]    (vendor/github.com/org/other)
```

#### `sync`

Re-wire all registered modules into all discovered projects. Clones any missing repos first.

```bash
devbot module sync
```

#### Configuration format

External modules are defined in `.devbot.global.jsonc` under the `"modules"` key. Each entry maps a name to a source and optional paths:

```jsonc
"modules": {
  "addyosmani": {
    "url": "https://github.com/addyosmani/agent-skills.git",
    "paths": {
      "agents": "agents",       // directory symlink — all files linked
      "skills": "skills",       // directory symlink — all files linked
      "memory": {
        "external/repo/path/instructions.md": "link/path/instructions.md"
        // file-level symlink — individual file wired at exact path
      }
    }
  }
}
```

**`paths` key semantics:**

- **String value** (`"skills": "skills"`) — the entire directory from the module is symlinked into `.opencode/<type>/<name>/` or `.agents/memory/<name>/`
- **Object value** (`"memory": { "source": "dest" }`) — each file is symlinked individually at its exact destination path. Used for `memory/` bootstrap files that must sit alongside internal bootstrap files without an extra nesting level
- **Missing paths** — if a path key is omitted, that module type is not wired

**Storage layout** (after wiring):

| Path                                       | Purpose                                          |
| ------------------------------------------ | ------------------------------------------------ |
| `<devbot-root>/.devbot.global.jsonc`       | Module registry (under `modules` key)            |
| `<devbot-root>/vendor/<org>/<repo>/`       | Cloned repository                                |
| `storage/external-agentic-modules/<name>/` | Wired module with full lifecycle (init.sh, etc.) |
| `<project>/.opencode/<type>/<name>`        | Symlink wired into each project                  |
| `<project>/.agents/memory/`                | Memory bootstrap files (file-level symlinks)     |

#### How it works

1. `add` registers the module in `.devbot.global.jsonc` under the `"modules"` key
2. For git URLs: clones into `vendor/<org>/<repo>`
3. For local paths: symlinks into `vendor/`
4. Discovers all initialized projects (those with `.agents/devbot.jsonc`)
5. Creates symlinks: `<project>/.opencode/<type>/<name>` → `<vendor>/<type>/`
6. `sync` repeats step 4-5 for all registered modules
7. `remove` removes symlinks and the config entry
