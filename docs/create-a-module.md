---
layout: page
title: Create a module
description: How to build a DevBot module and hook it up as an external module.
nav_section: docs
---

# Create a module

A module is a self-contained capability unit — skills, tools, hooks, commands, agents, or MCP servers — that DevBot wires into every project. You can build a module inside dev-bot (at `src/agentic/<name>/`) or in your own repository and register it as an **external module**.

## Module anatomy

Every module follows the same structure; **all entries are optional** — include only what your module needs. See [Module Reference](/module-reference) for the full anatomy.

```
<module>/
  agents/               Agent profiles
  commands/             Repeatable instruction sets invocable via agent input
  skills/               Agent-readable skill instructions (SKILL.md per skill)
  hooks/                Event-driven hooks
    git/                Git hooks (optional)
  hooks.json            Declarative hook manifest (harness-agnostic)
  tools/                Executable tools
    opencode/           TS thin wrapper for the OpenCode tool palette
    claudecode/         MCP server script
  memory/               Bootstrap files wired into `.agents/memory/` (external modules)
  tests/                BATS test suite
  install.sh            Idempotent OS dependency installer
  update.sh             Dependency update script
  init.sh               Per-project init + dependency self-heal
  up.sh                 Post-docker startup script
  pre.sh                Prerequisites check
  functions.sh          Thin wrapper sourcing `src/_shared/functions.sh`
  mcp.json              Canonical MCP server manifest (harness-agnostic — see [MCP configuration](/mcp-config))
  mcp.dynamic.json      Server-key prefixes this module writes at runtime (dynamic MCP emitters only)
  plugin.opencode.json  OpenCode plugin names declared by this module (optional)
  external-modules.json External module dependencies declared by this module
```

## 1. Scaffold the module

Create the directory and a `functions.sh` that sources the shared library:

```bash
# src/agentic/<name>/functions.sh
#!/usr/bin/env bash
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "$MODULE_DIR/../../_shared/functions.sh"
```

This gives your lifecycle scripts access to the shared helpers (`_info`, `_ok`, `_warn`, `_error`, `_step`, …).

## 2. Add capabilities

### Skills

Skills are `SKILL.md` files under `skills/<skill-name>/`, each with YAML frontmatter (`name` and `description` are required). Load the `devbot:create-skill` skill when authoring one.

```
skills/<skill-name>/SKILL.md
```

### Tools

Tools are `.ts` scripts (source of truth) with a thin `.sh` CLI wrapper. Place each tool in its own directory:

```
tools/<tool-name>/
  <tool-name>.ts    Source of truth — business logic + OpenCode tool export
  <tool-name>.sh    Thin CLI wrapper — delegates to the .ts via bun
```

The `.sh` wrapper **must** handle a `mcp-meta` subcommand that prints tool metadata as JSON — otherwise the tool is not exposed via the `devbot-tools` MCP server:

```bash
case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"my-tool","description":"What it does","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args"}},"required":["args"]}}
JSON
    exit 0 ;;
esac
```

Resolve your own directory symlink-safely (`readlink -f`) since tools are invoked through symlinks.

### Hooks

Declare hooks in `hooks.json` (harness-agnostic) — the business logic lives in `tools/`, and each harness wires the manifest through a single generic adapter (`on-hooks.ts` for OpenCode, `on-hooks.py` for Claude Code). See [Hooks](/hooks) for the schema and the six semantic events. Harness-specific side effects (e.g. prompt injection, two-phase trigger flows) stay hand-written in `src/harnesses/<harness>/hooks/`.

### Commands

Repeatable instruction sets under `commands/<command-name>.md`, with `name`/`description` frontmatter.

### Agents

Agent profiles under `agents/<name>.md`, with `name`, `description`, and `mode` (`primary` or `subagent`) frontmatter.

### MCP servers

Declare the MCP server(s) once in a canonical, harness-agnostic `mcp.json` — both harnesses register from it via the shared translator during `devbot init` (see [MCP configuration](/mcp-config) for the schema, tokens, and per-harness shapes):

```json
{
  "mcp": {
    "my-mcp": {
      "type": "stdio",
      "command": ["bash", "-c", "exec {harness-dir}/my-mcp-serve.sh"]
    }
  }
}
```

Enabling/disabling the module is the main gate. A server can also declare `"enabled": false` to ship **wired but not started** (the manifest entry below would become `"enabled": false,` right after `type`) — opencode registers it but does not start it; claudecode omits the server entirely, since `.mcp.json` has no per-server on/off. If the module's integration with a harness is plugin-based (like codebase-index on opencode), declare it in `plugin.opencode.json` instead — the opencode registration adapter skips plugin-provided servers to avoid double-loading.

A server whose definition is only known at init time (a detected port, a per-connection name) is written as a **runtime manifest** instead — `.opencode/<name>.mcp.json` / `.opencode/<name>-<detail>.mcp.json`, applied by the harness. Ship an `mcp.dynamic.json` next to `init.sh` declaring the key prefixes it writes (`{"prefixes": ["my-module"]}`): reset prunes a disabled emitter's `<prefix>` / `<prefix>-<detail>` keys by that declaration, never by module name alone — so a user's own `mcp.<some-module>` entry is not destroyed when a module that ships no MCP server is disabled. The prefix is the module directory name, written without the trailing hyphen an emitter may use internally (`aws`, not `aws-`).

### Documentation (`docs.md`)

A module ships its own documentation in a `docs.md` at the module root. The docs site build gathers it and publishes one page per module at `/modules/<area>/<name>`; a module without a `docs.md` gets **no page and no link anywhere** on the site.

Front matter declares the page and a concise manifest of what the module provides; the body is user-facing prose:

```markdown
---
title: My Module
description: One line — shown on the modules index and in the navigation.
skills: [my-skill]
mcps:
  my-mcp: What the server provides
---

What the module does, in a sentence or two.

## What it does

…

## Configuration

No project configuration is required.
```

- `description` is **required** — the build fails without it.
- `agents`, `commands`, `skills`, `hooks`, `plugins`, `tools` and `mcps` declare the module's capabilities. Each takes a plain list of names when the purpose can be read from the file itself (`SKILL.md`, an agent/command file, `hooks.json`, a tool's `# description:` header), and a `name: purpose` map where it cannot — typically `mcps`.
- The front matter subset is deliberately small: scalars, `[a, b]` flow lists, and one level of `name: purpose`. A YAML block scalar (`description: >-`) or block sequence (`- item`) **fails the build with an error** rather than being silently mis-read.
- The build generates a **Contents** table immediately before `## Configuration`, plus a capability-summary strip above the prose, from that manifest — so the manifest is what the reader sees.

`make docs-gather` builds the pages locally; `make docs` gathers and serves the site.

## 3. Lifecycle scripts

Dev-bot runs these automatically, identically for internal and external modules:

| Script       | When it runs                       | Purpose                                      |
| ------------ | ---------------------------------- | -------------------------------------------- |
| `pre.sh`     | `devbot install` / `devbot update` | Check prerequisites (non-destructive)        |
| `install.sh` | `devbot install`                   | Install OS-level dependencies (idempotent)   |
| `update.sh`  | `devbot update`                    | Update dependencies                          |
| `up.sh`      | `devbot up`                        | Post-docker startup (pull models, seed data) |
| `down.sh`    | `devbot down`                      | Pre-teardown cleanup                         |
| `init.sh`    | `devbot init`                      | Per-project init + dependency self-heal      |
| `reset.sh`   | `devbot reinit`                    | Reset per-project state                      |

All must be idempotent and source `functions.sh`.

### Module memory

A module whose behaviour needs always-on instructions writes them to
`<devbot_dir>/memory/active/modules/<module-name>.md` from its `init.sh` — one
file per module, never a section hand-copied into the project's `project.md`.

- `devbot reinit` deletes `active/modules/` before running init, so every
  enabled module rewrites its own file and a module that is disabled or no
  longer applies leaves nothing behind.
- `devbot init` adds `active/modules/` to the project's `.gitignore`: the files
  are generated output, not project content.
- Write the file before any environment-dependent early return in `init.sh` —
  the instructions describe the module, not the state of the machine, so an
  unreachable dependency must not drop them.
- Keep the text static. Anything that varies per project belongs in
  `project.md`; anything that varies per machine belongs in the module's
  `docs.md` or skill.

## 4. Test

Tests use the **bats** framework (fixtures in `tests/fixtures/`). `make test` auto-installs bats if missing.

## 5. Ship it as an external module

An external module is a standalone repo that only needs the artifact directories — DevBot clones it into `vendor/` and symlinks the artifacts into every project. Its lifecycle scripts (`pre.sh`, `install.sh`, `update.sh`, `up.sh`, `down.sh`, `init.sh`, `reset.sh`) are discovered at the repo root and run by DevBot exactly like internal modules, via `storage/external-agentic-modules/<name>/`.

### Layout in your own repo

Put the artifact directories at the repo root:

```
your-module/
  skills/      # each skill in its own subdirectory
  agents/      # agent .md files
  commands/    # command .md files
  plugins/     # hook/plugin files (optional)
  memory/      # bootstrap files wired into .agents/memory/ (optional)
  install.sh   # optional lifecycle scripts: pre/install/update/up/down/init/reset.sh
```

### Register it

**From a git URL** (clones into `vendor/`, auto-detects `./skills`, `./agents`, `./commands`, `./plugins`):

```bash
devbot module add https://github.com/you/your-module.git
devbot module add https://github.com/you/your-module.git --skills=./my-skills --agents=./my-agents
```

**From a local path** (no cloning — symlinked into `vendor/`; handy for local development):

```bash
devbot module add /path/to/your-module
```

**Declared by another module** — a module can ship an `external-modules.json` declaring its own dependencies, which dev-bot auto-merges into `.devbot.global.jsonc` during `devbot install`/`devbot update`:

```jsonc
{
  "your-module": {
    "url": "https://github.com/you/your-module.git",
    "paths": {
      "skills": "skills",
      "agents": "agents",
    },
  },
}
```

After registering, wire it into every project with:

```bash
devbot module sync     # or: devbot init <path>
```

### Config format

Registration writes an entry under the `external_modules` key of `.devbot.global.jsonc`:

```jsonc
"external_modules": {
  "your-module": {
    "url": "https://github.com/you/your-module.git",
    "paths": {
      "skills": "skills",            // directory symlink — all files linked
      "memory": {
        "bootstrap.md": "active/bootstrap.md"   // file-level symlink
      }
    }
  }
}
```

**`paths` semantics:**

- **String value** — the whole directory is symlinked into `.opencode/<type>/<name>/`.
- **Object value** — each file is symlinked individually at its exact destination (used for `memory/` bootstrap files).
- **Omitted key** — that artifact type is not wired.

## See also

- [Module Reference](/module-reference) — full anatomy and the `devbot module` CLI
- [Skills](/skills) / [Hooks](/hooks) / [MCPs](/mcps) — the shipped artifacts these follow
