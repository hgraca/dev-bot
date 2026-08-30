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
  init.sh               Per-project initialization
  up.sh                 Post-docker startup script
  pre.sh                Prerequisites check
  functions.sh          Thin wrapper sourcing `src/_shared/functions.sh`
  mcp.opencode.json     OpenCode MCP server definition
  mcp.claudecode.json   Claude Code MCP server definition
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

`mcp.opencode.json` (and `mcp.claudecode.json` for Claude Code) defines the MCP server and is auto-registered during `devbot init`:

```jsonc
{
    "my-mcp": {
        "type": "local",
        "command": ["bash", ".opencode/my-mcp-serve.sh"],
        "enabled": true,
    },
}
```

## 3. Lifecycle scripts

Dev-bot runs these automatically, identically for internal and external modules:

| Script       | When it runs                       | Purpose                                      |
| ------------ | ---------------------------------- | -------------------------------------------- |
| `pre.sh`     | `devbot install` / `devbot update` | Check prerequisites (non-destructive)        |
| `install.sh` | `devbot install`                   | Install OS-level dependencies (idempotent)   |
| `update.sh`  | `devbot update`                    | Update dependencies                          |
| `up.sh`      | `devbot up`                        | Post-docker startup (pull models, seed data) |
| `down.sh`    | `devbot down`                      | Pre-teardown cleanup                         |
| `init.sh`    | `devbot init`                      | Per-project initialization                   |
| `reset.sh`   | `devbot reinit`                    | Reset per-project state                      |

All must be idempotent and source `functions.sh`.

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

Registration writes an entry under the `modules` key of `.devbot.global.jsonc`:

```jsonc
"modules": {
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
