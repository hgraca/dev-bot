---
title: "CLI commands"
description: "The devbot command-line interface — lifecycle, management, and reporting commands."
commands: ["audit", "audit-fix"]
tools: ["list-projects"]
---

The `devbot` CLI is the single entry point for installing, configuring and running DevBot. It is installed to `$PATH` by `make install` and delegates each subcommand to a lifecycle script under `bin/`.

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

**Session teardown on exit.** Each `devbot` start registers a session in an install-level registry (`storage/run/sessions/`, gitignored) and holds a `flock` on its own file for the session's lifetime. When a session exits — normally, via Ctrl-C, or `kill` (the `flock` auto-releases even on `SIGKILL`) — it removes its file and, if **no other devbot session remains live**, runs `devbot down` to remove the devbot containers. If another session is still running (e.g. a second terminal in another project), the containers stay up — an explicit `devbot down` run in that state warns and keeps them, so it can never tear down a live session's containers. Containers are install-level (compose project `devbot`), shared by every session regardless of project, which is why the registry is install-level too. Volumes/mounted data (`storage/ollama`) are never touched. `devbot up`/`make up` alone start services without registering a session, so they are not auto-downed by a later harness exit.

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

`devbot up` is **consumer-driven**: a compose file is only included when its module is **enabled** in the `modules` map. A module that _needs_ a provider's service without running a container of its own ships a compose fragment that `include:`s the provider's compose — so enabling the consumer boots the provider even when the provider module is disabled (e.g. `codebase-index`'s fragment boots `ollama`, which is disabled by default). When no enabled module ships a compose file, the Docker section is skipped entirely and nothing is started. GPU detection (`gpu_enabled`) runs from `devbot install`/`update`, not the ollama module install, so it survives ollama being disabled.

`devbot down` is **not** module-scoped, and not project-scoped. Containers are install-level (one compose project `devbot`, shared by every session), so a module disabled _here_ may still own a container another project needs — removal therefore selects **every** discovered compose and runs `down --remove-orphans` (which also collects the datasources gateway, whose generated compose sits outside the discovery path). That is the same operation the last-session teardown runs. It is gated on the session registry: while any devbot session is alive it removes nothing and warns instead, because those containers serve that session too. There is no override flag.

Every dev-bot compose file declares `name: devbot` — the compose project name is read from the **first** `-f` file, and a consumer fragment is often first, so declaring the same name everywhere keeps all containers (ollama, litellm) in a single `devbot` project regardless of which fragment is merged first (otherwise ollama would boot under the fragment's directory name and `down`/orphan management would break). A test enforces the convention.

Because each container has a fixed `container_name` (`dev-bot-*`), a container left behind by a **different** compose project — e.g. one created before the project was renamed to `devbot`, or by a manual `docker run` — is invisible to `down --remove-orphans` yet blocks recreation with a name conflict. `devbot up` removes such containers before starting, so it self-heals instead of failing.

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

### `devbot stats [--days=N] [--project=DIR] [--all|-a] [--harness=HARNESS]`

Report tool usage, MCP-server usage, tool grades, and the most-used arguments for `bash`/`pty_spawn`/`skill`/`grep`/`glob`, as a Markdown report for the last `N` days (default: 30).

The command is harness-agnostic: it detects the harness (the `harness` setting, or `--harness`), delegates data gathering to that harness's stats adapter (`src/harnesses/<harness>/stats.sh`), validates the canonical JSON it returns, and renders the report. Without an adapter for the detected harness the command fails with a `FATAL`.

When the install-level grade matrix exists (`.agents/logs/tools-grades.csv`, written by `devbot:grade-tools`), the report gains a **Tool Grades** section: every tool's average grade over the rows where it was used (grade ≥ 1), highest first, plus `Min` (the worst grade it earned there) and `σ` (the spread across uses, shown only from three uses up). Tools never used are listed too, with a `—` average and zero uses. A `Poor ratings (1–3)` list follows with the de-duplicated reasons behind the low grades, taken from the matrix's `notes`. Grades are windowed and scoped exactly like the usage figures above them: `--days` bounds the rows, `--project` restricts them to one project.

A **Tool Quadrants** grid then places every tool on quality against demand: rows are `Avg > 3.5` and below, columns are `uses ≥` the demand bar and below. `workhorse` and `specialist` are keepers, `improve` means the capability is needed but the implementation disappoints, and `unproven` means too few uses to judge — a candidate, not a verdict. Tools never used sit below the grid. The demand bar is the median use count of the tools actually used, floored at 3, and is recomputed per report, so a tool can move quadrants as the matrix grows.

| Flag             | Description                                                 |
| ---------------- | ----------------------------------------------------------- |
| `--days=N`       | Report window in days (default: 30)                         |
| `--project=DIR`  | Restrict the report to one project directory                |
| `--all`, `-a`    | Aggregate every project (the default; accepted for clarity) |
| `--harness=NAME` | Force a harness adapter (default: configured harness)       |

```bash
devbot stats                          # last 30 days, every project
devbot stats --days=7                 # last week
devbot stats --project=../other-repo  # one project only
devbot stats --harness=claudecode
```

#### Writing a stats adapter

The parent command (`bin/stats.sh`) is harness-agnostic: it detects the harness, runs `src/harnesses/<harness>/stats.sh`, validates the JSON it prints, and renders the Markdown report (`src/_shared/render_stats.py`). Each harness owns only the **data gathering**; all presentation lives in the parent.

A stats adapter is invoked as:

```text
stats.sh --days <N> [--all | --project <dir>]
```

Without a scope flag (or with `--all`) the adapter aggregates every project; `--project` restricts it to one project directory. `--all` and `--project` are mutually exclusive.

and must print a single JSON object on stdout:

```json
{
  "schema": 1,
  "harness": "opencode",
  "days": 30,
  "scope": "current",
  "scope_label": "/path/to/project",
  "generated_at": "2026-09-10T16:40:00Z",
  "cost_kind": "estimated",
  "tools": [{ "name": "bash", "count": 27710, "tokens": 196400000, "cost": 12.34 }],
  "mcp_servers": [
    {
      "server": "devbot-tools",
      "count": 1500,
      "tokens": 210000,
      "cost": 0.5,
      "tools": [{ "name": "search-memories", "count": 1025, "tokens": 150000, "cost": 0.42 }]
    }
  ],
  "tool_arguments": {
    "bash": [{ "value": "git status", "count": 338 }],
    "skill": [{ "value": "devbot:software-development", "count": 42 }],
    "grep": [{ "value": "devbot_dir", "count": 20 }],
    "glob": [{ "value": "**/*.bats", "count": 15 }]
  }
}
```

| Field            | Required | Notes                                                                                                                                                                                                               |
| ---------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema`         | yes      | Contract version; currently `1`.                                                                                                                                                                                    |
| `harness`        | yes      | Harness name (shown in the report title).                                                                                                                                                                           |
| `days`           | yes      | Window, echoed into the report.                                                                                                                                                                                     |
| `scope`          | yes      | `all` (every project, the default) or `current` (one project, via `--project`).                                                                                                                                     |
| `scope_label`    | yes      | Human label (project path, or `all projects`).                                                                                                                                                                      |
| `generated_at`   | yes      | ISO-8601 timestamp.                                                                                                                                                                                                 |
| `cost_kind`      | yes      | `estimated`, `exact`, or `null`. Selects the cost column header — `estimated` renders `Cost (est.)`, anything else renders `Cost`. The column itself appears whenever any tool or MCP server has a non-null `cost`. |
| `tools[]`        | yes      | Every tool, native and MCP. `name` and `count` are required; `tokens` and `cost` may be `null`.                                                                                                                     |
| `mcp_servers[]`  | yes      | MCP aggregation: `server`, `count`, `tokens`, `cost`, and `tools[]` holding short tool names.                                                                                                                       |
| `tool_arguments` | no       | Optional argument aggregation for `bash`/`pty_spawn`/`skill`/`grep`/`glob` — a map of tool name to `[{ "value", "count" }]`. Tools absent from the map render no sub-table.                                         |

The parent validates the payload before rendering — a non-zero adapter exit, malformed JSON, missing required keys, or an unsupported `schema` fails the command.

The report contains a **Tool Usage** table, an **MCP Server Usage** table (shares are relative to MCP calls, not all tool calls), and a **Tool Arguments** section with one sub-table per aggregated tool.

The parent additionally reads the install-level grade matrix (`.agents/logs/tools-grades.csv`, written by `devbot:grade-tools`) and, after validation, injects an optional `tool_grades` block — **adapters must never emit it**. When present, the report gains a **Tool Grades** table (average, uses, worst grade, spread), a **Tool Quadrants** grid, and a **Poor ratings (1–3)** list; every tool in the block carries a `bucket`, the block reports the `days` window it was built with, and its `demand_bar` and `quality_threshold` are what the grid is drawn against. The parent passes its own `--days` to the helper, so the grades cover the same window as the usage figures — `rows` counts the rows in scope and in the window, while `total_rows` stays all-time as the denominator the window is shown against. Session ids are deliberately not counted: every subagent grades its own slice under its own session, so a session tally would measure agent count rather than how much evidence backs the table. A row the matrix left without a parseable `datetime` is placed by the dated rows around it: kept only when the nearest dated row before it and after it are both inside the window, dropped otherwise. The CSV path is overridable with `DEV_BOT_STATS_GRADES_CSV` (tests / out-of-tree installs); a missing or malformed CSV leaves the report unchanged.

To add an adapter for a new harness:

1. Create `src/harnesses/<name>/stats.sh` — a thin wrapper that runs your helper with `"$@"` (mirror the existing adapters).
2. Gather the data for the requested window (`--days`) and scope (every project by default, or the `--project` directory) and print the canonical JSON above, including `tool_arguments` when the harness exposes tool arguments.
3. Attribute cost/tokens as accurately as the harness allows. When cost can only be estimated, set `cost_kind` to `estimated`.
4. Keep presentation out of the adapter — the parent renders the Markdown.
5. Add BATS tests under `src/harnesses/<name>/tests/` using fixtures; never point tests at real user data.

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

## Configuration

The CLI manages two config files — `.devbot.global.jsonc` (install-level) and `.devbot.project.jsonc` (per project) — both written by `devbot install` / `devbot init` and never overwritten once they exist.

## See also

- [Configuration](/configuration) — the `.devbot.global.jsonc` / `.devbot.project.jsonc` files these commands manage
- [Module Reference](/module-reference) — module lifecycle and the `devbot module` CLI
- [OpenCode](/modules/harnesses/opencode) — the harness `devbot` starts
