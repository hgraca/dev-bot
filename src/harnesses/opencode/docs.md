---
title: "OpenCode"
description: "The OpenCode harness — hook adapter, module integrations, stats, and runtime footprint."
---

OpenCode is the default agent runtime DevBot plugs into. Each harness lives in `src/harnesses/<name>/` and is self-contained — it owns its hooks, wiring and config templates, while business logic stays in the agentic modules' `tools/` and the harness only adapts events into commands.

## The adapter

`src/harnesses/opencode/hooks/on-hooks.ts` is a single plugin: one `event` handler plus `tool.execute.before` / `tool.execute.after` cover all six semantic events declared by the agentic modules' `hooks.json` manifests.

| Event             | Meaning                         | OpenCode mapping                     |
| ----------------- | ------------------------------- | ------------------------------------ |
| `file.edited`     | a file was saved                | `event` (type `file.edited`)         |
| `command.before`  | a shell command is about to run | `tool.execute.before` (blocking)     |
| `command.after`   | a shell command finished        | `tool.execute.after` (success-gated) |
| `session.idle`    | the session went quiet          | `event` (type `session.idle`)        |
| `session.created` | a session started               | `event` (type `session.created`)     |
| `session.error`   | a transient provider error      | `event` (type `session.error`)       |

`skipOnCreate: true` is honoured by this adapter only — it skips dispatch when a `file.edited` is a file _create_, so a rewriting hook such as a formatter never normalizes a freshly-written file before the agent's next edit. `blocking: true` blocks when the command prints `{"blocked": true, "message": "…"}`. See [Hooks](/hooks) for the manifest schema, the `run` placeholders and the `match` filters.

## Module integrations

- **guards** — `command.before`, blocking. Registered as a `tool.execute.before` plugin that intercepts every shell tool call: the bash tool, and the PTY tools that launch or feed a command (`pty_spawn`, `pty_write`). No manual configuration needed.
- **format-md / format-json / format-yml** — `file.edited` with `skipOnCreate: true`; the formatter runs in the background on save.
- **graphify** — exposes the CLI as an OpenCode custom tool (`src/agentic/graphify/tools/opencode/graphify.ts`) with subcommands `query`, `path`, `explain`, `update`, `graph-stats`, `god-nodes`, plus a `serve`-backed MCP server.

## Stats

`src/harnesses/opencode/stats.py` reads the OpenCode SQLite database read-only. Cost and tokens are recorded per assistant step, so they are split evenly across the tools that step invoked (`cost_kind: estimated`). MCP tools are recognised by the server names declared in the project's OpenCode config (`mcp` block and `.opencode/*.mcp.json`), so native tools whose names contain underscores are not mistaken for MCP tools. It also aggregates `bash`/`pty_spawn`/`skill`/`grep`/`glob` arguments — shell invocations are normalised to `program subcommand` (first two tokens) after stripping a leading `cd … &&`, with `pty_spawn`'s executable and argument array re-joined first so both channels read alike.

The adapter contract is harness-agnostic — see [the `devbot stats` reference](/modules/tools/devbot-cli#writing-a-stats-adapter).

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

`tui.json` also accepts `plugin_enabled`, which switches off opencode's **built-in** TUI blocks by slot id. The shipped template disables `sidebar-context` only — the footer already shows context usage, so the sidebar copy is a duplicate. `internal:sidebar-files` is deliberately left **enabled**: it is the only file tree.

A dist-backed config is **seed-once**: `init.sh` writes it only when the file is absent, so from then on it is user-owned and a later change to a dist never reaches an existing project. Additions are reconciled, removals are not — every plugin the dists ship is re-added to an already-seeded config on every init/reinit (mirrored in `required-plugins.jsonc`, with a test asserting each dist entry appears there). Nothing is ever removed: "remove anything the dist does not list" would delete a project's own plugins.

#### PTY monitor

`src/harnesses/opencode/pty-monitor/` is dev-bot's own TUI plugin: it lists `opencode-pty` sessions in the sidebar (collapsible, with a bullet tinted green while running, red on a non-zero exit, muted otherwise) and opens a session's live output in a dialog on click. It also removes them on demand — a `✕` on each row and a `(clear finished)` action in the header. `opencode-pty` keeps a session in its in-memory map until it is _cleaned up_ (a plain kill retains it for log access), so finished sessions otherwise accumulate for the life of the opencode process — every `sleep`-wait and `make test` run leaves one behind. Removing a **running** session kills a live process, so it asks first; clearing finished ones never touches a live session, so it does not.

`opencode-pty` is a **hard dependency** — its HTTP API is the only window onto PTY sessions. Its server binds a random port and publishes it only by posting a message into the session; dev-bot reads the port from `/proc` instead (its own listening sockets). Starting the server is **never a side effect of load**: opencode awaits every TUI plugin factory before the TUI is usable, and a start goes through one of opencode-pty's commands, which runs server initialisation and needs a throwaway session. So loading resolves an already-running server by discovery alone, and a start happens only when asked — expanding the panel (collapsed by default) or running `/pty-monitor` starts it inside a throwaway session that is then deleted, so the URL message never litters your transcript. Off Linux there is no `/proc`, so that bootstrap is what resolves the origin.

#### Tool-details default

`src/harnesses/opencode/tui-defaults/` seeds dev-bot's opinion that **tool details start hidden**. "Hide tool details" is TUI runtime state — the `tool_details_visibility` boolean in opencode's kv store — not a config key, so no dist template can set it and a fresh install opens with details shown. The plugin writes the value at startup through the same reactive kv store opencode's own toggle uses.

The seed fires **only while the key is absent**: a value already in kv is an explicit choice and is never overridden, and the key being present makes every later start a no-op. Toggling the setting in the TUI is therefore the opt-out — an install or update never undoes it.

## Configuration

`opencode.jsonc` and `.opencode/tui.json` are written once from the harness templates (`opencode.dist.jsonc`, `tui.dist.jsonc`), then treated as user-owned — this is why an `lsp` override survives `devbot reinit`. Config is read once at startup: restart opencode after editing.

## See also

- [Claude Code](/modules/harnesses/claudecode) — the other harness
- [Hooks](/hooks) — the manifest schema and semantic events
- [MCP configuration](/mcp-config) — shared gateways and footprint
