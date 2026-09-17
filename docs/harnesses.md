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
| `scope`          | yes      | `current` or `all`.                                                                                                                                                                                                 |
| `scope_label`    | yes      | Human label (project path, or `all projects`).                                                                                                                                                                      |
| `generated_at`   | yes      | ISO-8601 timestamp.                                                                                                                                                                                                 |
| `cost_kind`      | yes      | `estimated`, `exact`, or `null`. Selects the cost column header — `estimated` renders `Cost (est.)`, anything else renders `Cost`. The column itself appears whenever any tool or MCP server has a non-null `cost`. |
| `tools[]`        | yes      | Every tool, native and MCP. `name` and `count` are required; `tokens` and `cost` may be `null`.                                                                                                                     |
| `mcp_servers[]`  | yes      | MCP aggregation: `server`, `count`, `tokens`, `cost`, and `tools[]` holding short tool names.                                                                                                                       |
| `tool_arguments` | no       | Optional argument aggregation for `bash`/`skill`/`grep`/`glob` — a map of tool name to `[{ "value", "count" }]`. Tools absent from the map render no sub-table.                                                     |

The parent validates the payload before rendering — a non-zero adapter exit, malformed JSON, missing required keys, or an unsupported `schema` fails the command.

The report contains a **Tool Usage** table, an **MCP Server Usage** table (shares are relative to MCP calls, not all tool calls), and a **Tool Arguments** section with one sub-table per aggregated tool.

### Adding a stats adapter for a new harness

1. Create `src/harnesses/<name>/stats.sh` — a thin wrapper that runs your helper with `"$@"` (mirror the existing adapters).
2. Gather the data for the requested window (`--days`) and scope (`--all` vs the current project) and print the canonical JSON above, including `tool_arguments` when the harness exposes tool arguments.
3. Attribute cost/tokens as accurately as the harness allows. When cost can only be estimated, set `cost_kind` to `estimated`.
4. Keep presentation out of the adapter — the parent renders the Markdown.
5. Add BATS tests under `src/harnesses/<name>/tests/` using fixtures; never point tests at real user data.

### Reference implementations

- **OpenCode** — `src/harnesses/opencode/stats.py`: reads the OpenCode SQLite database read-only. Cost and tokens are recorded per assistant step, so they are split evenly across the tools that step invoked (`cost_kind: estimated`). MCP tools are recognised by the server names declared in the project's OpenCode config (`mcp` block and `.opencode/*.mcp.json`), so native tools whose names contain underscores are not mistaken for MCP tools. It also aggregates `bash`/`skill`/`grep`/`glob` arguments — bash commands are normalised to `program subcommand` (first two tokens) after stripping a leading `cd … &&`.
- **Claude Code** — `src/harnesses/claudecode/stats.py`: parses the session transcripts under `~/.claude/projects/<slug>/**/*.jsonl` (including subagents). Tokens come from each assistant message's `usage`; transcripts carry no cost data, so `cost_kind` is `null` and the report shows a Tokens column instead of Cost. It aggregates `Bash`/`Skill`/`Grep`/`Glob` arguments with the same normalisation.

## Runtime footprint

Each harness instance starts its own helper processes. Two levers keep that cost down per project.

### LSP servers

opencode auto-starts a language server for every language it detects in the project (the `lsp` field in `opencode.jsonc`, default `true`). Each server is a separate process costing roughly 100–250 MB per instance — measured in this repo: pyright ~119 MB, bash-language-server ~107 MB; on PHP projects intelephense is the heaviest.

Disable the ones a project doesn't need by turning `lsp` into an object — the object form keeps every other built-in enabled:

```jsonc
// opencode.jsonc
"lsp": {
    "intelephense": { "disabled": true }
}
```

`opencode.jsonc` is written once from the template and then treated as user-owned, so this override survives `devbot reinit`. Config is read once at startup — restart opencode after editing.

### MCP servers

See [MCP configuration](/mcp-config#reducing-the-footprint) — heavy servers are dropped by disabling their module.

### TUI plugins

opencode loads **two separate plugin surfaces**, and the distinction is enforced by their schemas:

| Surface | File                            | Takes                                       |
| ------- | ------------------------------- | ------------------------------------------- |
| Server  | `opencode.jsonc` → `plugin`     | plugins that hook events and register tools |
| TUI     | `.opencode/tui.json` → `plugin` | plugins that render into the terminal UI    |

`opencode.json`'s schema declares no `tui` key and sets `additionalProperties: false`, so a TUI plugin listed there is **schema-invalid and opencode refuses to start**. Each surface therefore gets its own template: `opencode.dist.jsonc` and `tui.dist.jsonc`, both applied by `_write_jsonc_from_dist` on first init and user-owned afterwards.

Unlike hooks, **TUI plugins are not auto-discovered** — they only load if named in `tui.json`'s `plugin` array. dev-bot's own TUI plugins are symlinked into `.opencode/tui-plugins/` by `init.sh` (`_link_tui_plugins`), removed by `reset.sh`, and referenced from the template by a path **relative** to `tui.json`, so the shipped template carries no install path.

`tui.json` also accepts `plugin_enabled`, which switches off opencode's **built-in** TUI blocks by slot id (`internal:sidebar-context`, `-files`, `-footer`, `-lsp`, `-mcp`, `-todo`, `internal:home-footer`, `-tips`, `internal:notifications`, `internal:plugin-manager`). The shipped template disables `sidebar-context` only — the footer already shows context usage, so the sidebar copy is a duplicate. `internal:sidebar-files` is deliberately left **enabled**: it is the only file tree, since a third-party plugin that also drew one was dropped rather than carried as a duplicate.

A dist-backed config is **seed-once**: `init.sh` writes it only when the file is absent, so from then on it is user-owned and a later change to a dist never reaches an existing project. That cuts both ways, and both were hit in practice — a plugin entry added to a dist never arrived (leaving a shipped feature wired without its dependency), and one **removed** from a dist never left (leaving a project running something the toolkit had dropped).

Additions are reconciled, removals are not. **Every** plugin the dists ship — mirrored in `required-plugins.jsonc`, with a test asserting each dist entry appears there so a new one cannot be forgotten — is re-added to an already-seeded config on every init/reinit, so a project converges on the set the harness actually runs with. The dist's other keys (agent models, permissions, `watcher.ignore`, `lsp`) are never touched, and neither is any plugin a project added itself. Nothing is ever removed: "remove anything the dist does not list" would delete a project's own plugins, so a project that has diverged by keeping something no longer shipped is corrected deliberately, by hand.

Note also that the reinit-on-start is gated by a hash of the **config** files, not of harness code, so a wiring change reaches existing projects only through a released update or an explicit `devbot reinit`.

#### PTY monitor

`src/harnesses/opencode/pty-monitor/` is dev-bot's own TUI plugin: it lists `opencode-pty` sessions in the sidebar (collapsible, with a bullet tinted green while running, red on a non-zero exit, muted otherwise) and opens a session's live output in a dialog on click.

`opencode-pty` is a **hard dependency** — its HTTP API is the only window onto PTY sessions. Two consequences worth knowing:

- Its server binds a **random port and publishes it only by posting a message into the session**. dev-bot reads the port from `/proc` instead (its own listening sockets), and when the server isn't running yet it starts it inside a **throwaway session** and deletes it — so the URL message never litters your transcript. Off Linux there is no `/proc`, so that bootstrap is what resolves it.
- With no PTY session the panel is legitimately empty.

## See also

- [Hooks](/hooks) — the manifest schema and semantic events
- [Module Reference](/module-reference) — agentic module anatomy
