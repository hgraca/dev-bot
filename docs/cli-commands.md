---
layout: page
title: Cli commands
description: The devbot command-line interface — lifecycle and management commands.
nav_section: docs
---

# Cli commands

The `devbot` CLI is the single entry point for installing, configuring, and running DevBot. It is installed to `$PATH` by `make install` and delegates each subcommand to a lifecycle script under `bin/`.

## Quick start

```bash
git clone git@github.com:hgraca/dev-bot.git && cd dev-bot
make install                 # install once (writes .devbot.global.jsonc)
cd path/to/your-project
devbot init                  # wire the project (writes .devbot.project.jsonc)
devbot                       # start the harness (opencode or claudecode)
```

## Commands

### `devbot` — start the harness

Run with no subcommand (or any unknown argument) inside a project to start the configured harness (`opencode` or `claudecode`, per the `harness` setting) after running `devbot up`. Outside a project it prints help.

### `devbot help`

Show the full command reference.

### `devbot install`

Install all tools. Idempotent — safe to re-run. Writes `.devbot.global.jsonc` on first run.

### `devbot update`

Pull the latest dev-bot from git and run every tool's update script.

### `devbot init [path]`

Initialize dev-bot in a project directory (default: current directory). Writes `.devbot.project.jsonc` and wires modules into `.opencode/` and `.agents/`.

### `devbot reinit [--all|-a]`

Re-initialize the current project, or all registered projects with `--all`.

### `devbot up` / `devbot down`

Start / stop the Docker services (Ollama, LiteLLM) via auto-discovered compose files.

### `devbot tool <name> [args...]`

Run a dev-bot tool by name (e.g. `devbot tool tree`, `devbot tool git-report`). Run `devbot tool` with no name to list available tools.

### `devbot list <type> [-a|--all]`

List agentic artifacts as a markdown table. `type` is one of:

| Type       | What it lists                           |
| ---------- | --------------------------------------- |
| `commands` | Slash commands                          |
| `agents`   | Agent definitions                       |
| `skills`   | Skills                                  |
| `hooks`    | OpenCode plugin hooks                   |
| `mcps`     | MCP servers                             |
| `tools`    | Tools (the `devbot-tools` MCP tool set) |

`-a` / `--all` includes artifacts from disabled modules.

### `devbot prune [days] [--all|-a]`

Prune old OpenCode sessions (default: 30 days).

### `devbot models <subcommand>`

Manage LLM models via Ollama:

| Subcommand       | Description                    |
| ---------------- | ------------------------------ |
| `pull <model>`   | Pull a model from the registry |
| `list-local`     | List locally cached models     |
| `list-remote`    | Browse remote models           |
| `remove <model>` | Remove a locally cached model  |

### `devbot module <subcommand>`

Manage external modules (see [Module Reference](/module-reference) for details):

| Subcommand      | Description                                |
| --------------- | ------------------------------------------ |
| `install`       | Clone/pull configured external modules     |
| `init [path]`   | Wire modules into `.opencode/` directories |
| `add <url       | path>`                                     | Register a module (git URL or local path) |
| `remove <name>` | Unregister a module                        |
| `list`          | List registered modules                    |
| `sync`          | Re-wire all modules (alias for `init`)     |

## See also

- [Configuration](/configuration) — the `.devbot.global.jsonc` / `.devbot.project.jsonc` files these commands manage
- [Module Reference](/module-reference) — module lifecycle and the `devbot module` CLI
