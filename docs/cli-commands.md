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

**Auto-update.** Before wiring, a bare start runs `devbot update --auto` — a quiet no-op when already on the newest release. A version change rewrites the global config's `version`, which triggers a per-project reinit on this project's start and on every other project's next start. Set the global `auto_update` to `false` to opt out. A failed update (offline, conflict) warns and the start continues on the current version.

Startup delegates to the harness module's `start.sh` (`src/harnesses/<harness>/start.sh`), which launches the harness binary with no forced agent — the session agent comes from the project's default (`opencode.jsonc` `default_agent` / `.claude/settings.json` `agent`), which `init` creates with DevBot by default and only asks to change when an existing config chose a different agent. Before launching, `start.sh` rotates the previous session's `.agents/logs/*.log` files to `.agents/logs/rotated/<date>-<name>-<NNN>.log` (old logs preserved); when the harness exits it scans the fresh logs for error-level entries, alerts you if any were written, and preserves the harness's exit code.

**Harness-arg passthrough.** Anything after the first `--` is forwarded verbatim to the harness binary; tokens before it are devbot's own and are never forwarded. Without `--`, every argument is forwarded unchanged (the "unknown argument" behaviour above). This is the escape hatch for flags that collide with devbot's own (`-h`/`--help`/`--version` and known subcommand names):

```bash
devbot -- -h                 # opencode/claude help (not devbot help)
devbot -- run "fix the bug"  # opencode run; claude -p style one-shot
devbot -c "msg"              # no --: forwards as today
devbot foo -- -c "msg"       # foo is consumed; only -c "msg" reaches the harness
```

Only the first `--` splits — a later `--` is a literal part of the harness argv. Arguments keep their boundaries (quoting survives the split).

**Session teardown on exit.** Each `devbot` start registers a session in an install-level registry (`storage/run/sessions/`, gitignored) and holds a `flock` on its own file for the session's lifetime. When a session exits — normally, via Ctrl-C, or `kill` (the `flock` auto-releases even on `SIGKILL`) — it removes its file and, if **no other devbot session remains live**, runs `devbot down` to remove the devbot containers. If another session is still running (e.g. a second terminal in another project), the containers stay up. Containers are install-level (compose project `devbot`), shared by every session regardless of project, which is why the registry is install-level too. Volumes/mounted data (`storage/ollama`) are never touched. `devbot up`/`make up` alone start services without registering a session, so they are not auto-downed by a later harness exit.

### `devbot help`

Show the full command reference.

### `devbot install`

Install all tools. Idempotent — safe to re-run. Writes `.devbot.global.jsonc` on first run.

### `devbot update [tag] [--auto]`

Move the install to the newest **release tag** (or an explicit tag: `devbot update <tag>` pins/downgrades). Fetches tags from origin, and is a clean no-op when already on the newest tag. On a real move it refreshes tools, agentic modules, and external modules, then records the release in the global config's `version` so every project reinits on its next start. `--auto` is the quiet, non-interactive form used by the bare `devbot` start — a single-line no-op that never prompts; without it the usual update output is printed.

### `devbot init [path]`

Initialize dev-bot in a project directory (default: current directory). Writes `.devbot.project.jsonc` and wires modules into `.opencode/` and `.agents/`.

### `devbot reinit [--all|-a]`

Re-initialize the current project, or all registered projects with `--all`.

### `devbot up` / `devbot down`

Start / stop the Docker services via auto-discovered compose files across all modules (`src/tools`, `src/agentic`, `src/harnesses`).

Docker services are **consumer-driven**: a compose file is only included when its module is **enabled** in the `modules` map. A module that _needs_ a provider's service without running a container of its own ships a compose fragment that `include:`s the provider's compose — so enabling the consumer boots the provider even when the provider module is disabled (e.g. `codebase-index`'s fragment boots `ollama`, which is disabled by default). When no enabled module ships a compose file, the Docker section is skipped entirely and nothing is started/stopped. GPU detection (`gpu_enabled`) runs from `devbot install`/`update`, not the ollama module install, so it survives ollama being disabled.

Every dev-bot compose file declares `name: devbot` — the compose project name is read from the **first** `-f` file, and a consumer fragment is often first, so declaring the same name everywhere keeps all containers (ollama, litellm) in a single `devbot` project regardless of which fragment is merged first (otherwise ollama would boot under the fragment's directory name and `down`/orphan management would break). A test enforces the convention.

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

### `devbot stats [--days=N] [--all|-a] [--harness=HARNESS]`

Report tool usage, MCP-server usage, and the most-used arguments for `bash`/`skill`/`grep`/`glob`, as a Markdown report for the last `N` days (default: 30).

The command is harness-agnostic: it detects the harness (the `harness` setting, or `--harness`), delegates data gathering to that harness's stats adapter (`src/harnesses/<harness>/stats.sh`), validates the canonical JSON it returns, and renders the report. Without an adapter for the detected harness the command fails with a `FATAL`.

| Flag             | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `--days=N`       | Report window in days (default: 30)                   |
| `--all`, `-a`    | Aggregate every project (default: current project)    |
| `--harness=NAME` | Force a harness adapter (default: configured harness) |

```bash
devbot stats                      # last 30 days, current project, configured harness
devbot stats --days=7             # last week
devbot stats --days=90 --all      # every project, last quarter
devbot stats --harness=claudecode
```

Adding support for a new harness is a single adapter script — see [Harnesses](/harnesses#stats-adapters).

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
