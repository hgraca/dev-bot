---
layout: page
title: Cli commands
description: The devbot command-line interface — lifecycle and management commands.
nav_section: docs
---

# Cli commands

The `devbot` CLI is the single entry point for installing, configuring, and running DevBot. It is installed to `$PATH` by `make install` and delegates each subcommand to a lifecycle script under `bin/`.

## Quick start

<div class="hero-install">
  <button type="button" class="hero-install-cmd"
          data-install-org="{{ site.install_org | default: 'GET-E' }}"
          data-install-repo="{{ site.install_repo | default: 'dev-bot' }}"
          aria-label="Copy install command">
    <span class="hero-install-cmd-text">$ curl -fsSL https://get-e.github.io/dev-bot/install.sh | bash -s -- --ssh</span>
    <span class="hero-install-copy-status">
      <svg class="hero-install-copy-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
      <svg class="hero-install-copy-check" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.75 15.0938L9 20.25L21.25 3.75"></path></svg>
    </span>
  </button>
</div>

Installs to `~/.local/share/dev-bot` and links the `devbot` CLI into `~/.local/bin` (override the location with `--install-dir` or `DEV_BOT_INSTALL_DIR`). Re-running the install command is idempotent — it pulls the latest version and reinstalls in place; use `devbot update` to refresh an existing install.

Install once, then in any project:

```bash
devbot init                  # wire the project (writes .devbot.project.jsonc)
devbot                       # start the harness (opencode or claudecode)
```

## Commands

### `devbot` — start the harness

Run with no subcommand (or any unknown argument) inside a project to start the configured harness (`opencode` or `claudecode`, per the `harness` setting) after running `devbot up`. Outside a project it prints help.

Startup delegates to the harness module's `start.sh` (`src/harnesses/<harness>/start.sh`), which launches the harness binary with no forced agent — the session agent comes from the project's default (`opencode.jsonc` `default_agent` / `.claude/settings.json` `agent`), which `init` creates with DevBot by default and only asks to change when an existing config chose a different agent. Before launching, `start.sh` rotates the previous session's `.agents/logs/*.log` files to `.agents/logs/rotated/<date>-<name>-<NNN>.log` (old logs preserved); when the harness exits it scans the fresh logs for error-level entries, alerts you if any were written, and preserves the harness's exit code.

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
