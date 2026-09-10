---
layout: page
title: Harnesses
description: How DevBot's harness adapters map declarative hooks to each agent runtime.
nav_section: docs
---

# Harnesses

A **harness** is an agent runtime DevBot plugs into — currently OpenCode and Claude Code. Each lives in `src/harnesses/<name>/` and is self-contained: it owns its hooks, wiring, and config templates. Business logic stays in the agentic modules' `tools/`; the harness only adapts events → commands.

## The adapter contract

Each harness ships one **generic adapter** that reads every `src/agentic/*/hooks.json` manifest and maps the six semantic events to the harness's hook API:

| Event             | Meaning                         | OpenCode mapping                     |
| ----------------- | ------------------------------- | ------------------------------------ |
| `file.edited`     | a file was saved                | `event` (type `file.edited`)         |
| `command.before`  | a shell command is about to run | `tool.execute.before` (blocking)     |
| `command.after`   | a shell command finished        | `tool.execute.after` (success-gated) |
| `session.idle`    | the session went quiet          | `event` (type `session.idle`)        |
| `session.created` | a session started               | `event` (type `session.created`)     |
| `session.error`   | a transient provider error      | `event` (type `session.error`)       |

The manifest `run` command resolves placeholders `{module}`, `{file}`, `{command}`, `{agent}`, `{hash}`, `{session-id}`, `{error}`, `{worktree}`, `{global-config}`, `{project-config}`. `match` filters by `file` (path regex), `content` (first-4KB regex), `tool`, or `command`. `blocking: true` blocks when the command prints `{"blocked": true, "message": "…"}`. `skipOnCreate: true` (honored by the opencode adapter only) skips dispatch when the `file.edited` is a file _create_ — rewriting hooks such as the formatters opt out of creates so a freshly-written file is never normalized before the agent's next edit (audit-48 FAIL-1); read-only hooks leave it unset so they still fire on creates. See [Hooks](/hooks) for the manifest schema.

## The adapters

- **OpenCode** — `src/harnesses/opencode/hooks/on-hooks.ts`: one plugin; a single `event` handler plus `tool.execute.before`/`tool.execute.after` cover all six events.
- **Claude Code** — `src/harnesses/claudecode/hooks/on-hooks.py`: a five-phase dispatcher (`pre-tool` / `post-file` / `post-bash` / `stop` / `startup`), because Claude Code's hook events are separate registrations with no unified event stream.

## Exceptions

`devbot:auto-recover` stays hand-written (in both harnesses) because its side effects don't fit the "run a command" model: OpenCode injects the recovery prompt via `client.session.prompt`, and Claude Code uses a two-phase PostToolUse → Stop trigger flow.

## Adding a new harness

See the `devbot:create-devbot-module` skill's annex (`references/harness-adapter.md`) for the step-by-step: create `src/harnesses/<name>/` with `functions.sh`, write the generic adapter that maps the six events, honor the blocking contract, write `init.sh` to wire it, and register it in `bin/init.sh`'s discovery loop.

## Stats adapters

`devbot stats` reports tool usage and MCP-server usage. The parent command (`bin/stats.sh`) is harness-agnostic: it detects the harness, runs `src/harnesses/<harness>/stats.sh`, validates the JSON it prints, and renders a Markdown report (`src/_shared/render_stats.py`). Each harness owns only the **data gathering**; all presentation lives in the parent.

### The canonical JSON contract (schema v1)

A stats adapter is invoked as:

```
stats.sh --days <N> [--all]
```

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
    ]
}
```

| Field           | Required | Notes                                                                                                                                                                                                               |
| --------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema`        | yes      | Contract version; currently `1`.                                                                                                                                                                                    |
| `harness`       | yes      | Harness name (shown in the report title).                                                                                                                                                                           |
| `days`          | yes      | Window, echoed into the report.                                                                                                                                                                                     |
| `scope`         | yes      | `current` or `all`.                                                                                                                                                                                                 |
| `scope_label`   | yes      | Human label (project path, or `all projects`).                                                                                                                                                                      |
| `generated_at`  | yes      | ISO-8601 timestamp.                                                                                                                                                                                                 |
| `cost_kind`     | yes      | `estimated`, `exact`, or `null`. Selects the cost column header — `estimated` renders `Cost (est.)`, anything else renders `Cost`. The column itself appears whenever any tool or MCP server has a non-null `cost`. |
| `tools[]`       | yes      | Every tool, native and MCP. `name` and `count` are required; `tokens` and `cost` may be `null`.                                                                                                                     |
| `mcp_servers[]` | yes      | MCP aggregation: `server`, `count`, `tokens`, `cost`, and `tools[]` holding short tool names.                                                                                                                       |

The parent validates the payload before rendering — a non-zero adapter exit, malformed JSON, missing required keys, or an unsupported `schema` fails the command.

### Adding a stats adapter for a new harness

1. Create `src/harnesses/<name>/stats.sh` — a thin wrapper that runs your helper with `"$@"` (mirror the existing adapters).
2. Gather the data for the requested window (`--days`) and scope (`--all` vs the current project) and print the canonical JSON above.
3. Attribute cost/tokens as accurately as the harness allows. When cost can only be estimated, set `cost_kind` to `estimated`.
4. Keep presentation out of the adapter — the parent renders the Markdown.
5. Add BATS tests under `src/harnesses/<name>/tests/` using fixtures; never point tests at real user data.

### Reference implementations

- **OpenCode** — `src/harnesses/opencode/stats.py`: reads the OpenCode SQLite database read-only. Cost and tokens are recorded per assistant step, so they are split evenly across the tools that step invoked (`cost_kind: estimated`). MCP tools are recognised by the server names declared in the project's OpenCode config (`mcp` block and `.opencode/*.mcp.json`), so native tools whose names contain underscores are not mistaken for MCP tools.
- **Claude Code** — `src/harnesses/claudecode/stats.py`: parses the session transcripts under `~/.claude/projects/<slug>/*.jsonl`. Tokens come from each assistant message's `usage`; transcripts carry no cost data, so `cost_kind` is `null` and the report shows a Tokens column instead of Cost.

## See also

- [Hooks](/hooks) — the manifest schema and semantic events
- [Module Reference](/module-reference) — agentic module anatomy
