---
title: "OpenCode v2"
description: "The OpenCode 2.x harness — plugin and config shapes, the v1 session-store migration, and the TUI surfaces ported alongside them."
---

# opencode-v2

Harness adapter for the **OpenCode 2.x** line. Selected with the root scalar:

```jsonc
// .devbot.project.jsonc
{ "harness": "opencode-v2" }
```

`harness` is the only enablement switch. A name in the `modules` map is ignored,
and every other directory under `src/harnesses/` is disabled while this one is
selected.

## Why a second module

OpenCode 2 replaced the plugin API outright. A V1 plugin returns one object of
tools and hooks; a V2 plugin default-exports `Plugin.define({ id, setup(ctx) })`
from `@opencode/plugin` and registers each hook on the domain that owns it.
V1 plugin implementations **do not run** on a V2 host, so `src/harnesses/opencode/`
cannot be reused by renaming files or config keys.

The v1 adapter therefore refuses a 2.x host (`_devbot_require_opencode_1x`), and
this one refuses a 1.x host (`_devbot_require_opencode_2x`). `_devbot_opencode2_bin`
resolves the 2.x binary: `OPENCODE2_BIN` if set, then a plain `opencode` on
`PATH` **when its `--version` reports 2.x**, then `~/.opencode/bin/opencode2`,
`~/.opencode/v2/opencode`, and `opencode2` on `PATH`. A 1.x `opencode` is never a
candidate — it belongs to the other harness.

## What differs from v1

| Concern          | v1                                            | v2                                           |
| ---------------- | --------------------------------------------- | -------------------------------------------- |
| Config file      | `opencode.jsonc`, `tui.json`                  | `opencode.jsonc` (same name, new key shapes) |
| Hooks            | V1 object returned from the plugin function   | `Plugin.define` + per-domain `hook()`        |
| Plugins key      | `plugin: [...]`                               | `plugins: [{ package, options }]`            |
| MCP key          | `mcp: { <name>: { enabled } }`                | `mcp.servers: { <name>: { disabled } }`      |
| Permissions      | `permission` object                           | `permissions` ordered array, last match wins |
| Agents           | `agent` map (`prompt`, `disable`)             | `agents` map (`system`, `disabled`)          |
| Providers        | `provider` (`npm`)                            | `providers` (`package`, `aisdk:` prefix)     |
| TUI parts        | project `tui.json` + `.opencode/tui-plugins/` | plugin package `exports["./tui"]`            |
| Instruction file | `AGENTS.md`, `CLAUDE.md` fallback             | `AGENTS.md` only                             |

Two behavioural traps carried from the V1→V2 migration: `external_directory` is
**allowed by default** in V2, so the seeded config adds an explicit rule to keep
V1 behaviour; and `lsp` is accepted but **inert** — V2 runs no language servers
and emits no diagnostics.

## Deliberately not ported

These v1 files have no working v2 counterpart and are omitted rather than
shipped as dead weight:

- `lsp/intelephense.sh`, `lsp/reap.sh` — V2 runs no language servers.
- `strip_opencode_diagnostics.py` — V2 emits no diagnostics to strip.
- `tui.dist.jsonc` — V2 reads one global `~/.config/opencode/cli.json`; there is
  no project-local client config to seed.

## Directory ownership

Verified on a 2.3.0 host:

- **v2 auto-loads every directory under `.opencode/plugins/`.** Adding a
  `plugins` entry that names one registers the same plugin twice; the host keeps
  the first and fails the second with `Duplicate plugin ID`, which the TUI
  reports as a **failed** plugin. This harness therefore writes the shim
  directories and leaves `plugins` empty — `init.sh` also drops such entries
  from a config seeded before the rule held.
- **A symlinked plugin entry is skipped.** The entry must be a real file, so
  `init.sh` writes a small shim that re-exports the module's own source:
  `export { default } from "<DEV_BOT_ROOT>/src/harnesses/opencode-v2/hooks/x.ts"`.
  `import.meta.dir` inside the real module still resolves to the module, so
  there is one source of truth.

Both harnesses share `.opencode/plugins/`, and isolation comes from a
handover sweep rather than from separate directories:

- v1 writes `*.ts` files there; v2 writes `<name>/index.ts` directories.
- On init, v2 removes every symlink under `.opencode/` that resolves under
  `DEV_BOT_ROOT`, so a deselected v1 adapter's plugins cannot be auto-loaded.
- User files and `.opencode/opencode.json` are never touched.

V1's `reset.sh` exits when it is not the selected harness by design, so the
incoming harness does the cleaning.

## Version support

`_devbot_require_opencode_2x` reads the resolved binary's `--version` and refuses
the 1.x line. It fails open on a missing binary and on an unparseable version,
and allows a source build reporting `0.0.0--<timestamp>`.

## Config migration

Both harnesses read the **same** `opencode.jsonc`, so a project that once ran
the v1 adapter already has a v1 document. `init.sh` converts it once, through
`lib/migrate_v1.py`, and leaves `opencode.jsonc.pre-v2.bak` beside it:

| v1                                              | v2                                               |
| ----------------------------------------------- | ------------------------------------------------ |
| `plugin` (strings and `[name, options]` tuples) | `plugins` (strings, or `{package, options}`)     |
| `permission` (object per tool)                  | `permissions` (ordered rules, last match wins)   |
| `agent` (`prompt`, `disable`, `variant`)        | `agents` (`system`, `disabled`, `model#variant`) |
| `provider` (`npm`, `options`)                   | `providers` (`package`, `settings`)              |
| `mcp.<name>` with `enabled`                     | `mcp.servers.<name>` with `disabled` (inverted)  |
| `lsp`                                           | dropped — v2 runs no language servers            |

Permission keys with no v2 action are dropped rather than mistranslated:
`list`, `todowrite`, `todoread`, `codesearch`, `doom_loop`, `lsp`.

## Agent PTY

v1 pinned `opencode-pty@0.3.6`. Its published builds still depend on
`@opencode-ai/plugin ^1.3.13`, and V1 plugin implementations do not run on a V2
host, so there is no upstream build to pin. `hooks/pty.ts` provides the five
tools (`pty_spawn`, `pty_write`, `pty_read`, `pty_list`, `pty_kill`) directly via
`ctx.tool.transform`, backed by `bun-pty`, which `init.sh` installs with `bun install` (~2s). The
scaffold declares **only** bun-pty: `@opencode/plugin` is resolved by the host at
runtime, and listing it pulls its full dependency graph on every install for no
benefit. The plugin also resolves bun-pty from the project's
`.opencode/node_modules` as a fallback, because the re-export shim makes a bare
specifier resolve against the dev-bot checkout instead. If it cannot be
resolved the tools still register and return an actionable message rather than
vanishing from the toolset.

Verified end to end on a 2.3.0 host: spawn → read (`hello-from-pty`, exit 0) →
kill. A tool result carrying `output` must declare an output schema — without
one the whole result fails to serialise and the model retries, so these tools
return content only.

## TUI parts

V2 keeps TUI plugins, but as a **part of a plugin package** mounted by the
terminal UI. opencode 2.3 validates the `./tui` default export as
`{ id: string, setup(ctx) }`; a module shaped any other way is rejected with
`Invalid V2 TUI plugin module` and shows up as a failed TUI plugin.

- A local plugin directory with **no** `package.json` is read through bare file
  names at its root: `index.ts` is the server part and `tui.ts` the TUI part.
- A package with only a TUI part belongs in the global
  `~/.config/opencode/cli.json`, not in a project config.
- opencode 2.3 still **applies** a project `.opencode/tui.json` if one exists,
  but v2 declares no project-local client config. The v1 seed re-declared
  `opencode-tabs@0.3.0` and three `./tui-plugins/*` paths, so `init.sh` retires
  exactly those entries and leaves the project's own additions alone.

**Shipped:** `provider-ttft` (`tui/provider-ttft/`), linked as
`.opencode/plugins/provider-ttft/` with a server part and the TUI row. It reads
`time.firstToken` / `time.created` from `message.updated` — 2.3 stamps both on
the assistant message — and renders `TTFT 1.2s` at the top of `sidebar.content`
(`prepend`; every built-in block appends).

**Not ported:** `pty-monitor` and `tui-defaults`. Both were written against the
pre-2.3 API (`kv`/`slots`/`events`), which 2.3 no longer exposes, so linking them
only produced `Invalid V2 TUI plugin module` on every start. `tui-defaults` is
the harder one: its only job is seeding the tool-details kv default, and 2.3 has
no plugin-facing kv surface to seed.

### Sidebar blocks are plugins

Every built-in sidebar section is a bundled TUI plugin, so the lever is its id,
not a slot name:

| Built-in                   | Slot              | What it renders         |
| -------------------------- | ----------------- | ----------------------- |
| `opencode.sidebar.context` | `sidebar.content` | context percent + spend |
| `opencode.sidebar.todo`    | `sidebar.content` | the session's todo list |
| `opencode.sidebar.mcp`     | `sidebar.content` | MCP server state        |
| `opencode.sidebar.limit`   | `sidebar.content` | rate-limit windows      |
| `opencode.sidebar.footer`  | `sidebar.footer`  | location / branch       |

v2 takes terminal settings from the global `cli.json`. Disable one with a
`-<id>` directive in `plugins`; entries are processed in order, so the directive
has to come after anything that would re-enable it:

```json title="cli.json"
{ "plugins": ["-opencode.sidebar.context"] }
```

`plugin_enabled` is the **legacy `tui.json`** key: it no longer reaches the
plugin list from `cli.json`, which is why dropping the block needs the directive
form. The v1 ids (`internal:sidebar-context`) match nothing on 2.3.

Third-party TUI plugins have the same requirement: `opencode-tabs@0.3.0`
exports `{ id, tui }` and registers through `api.slots`, so it cannot load on
2.3, and 2.3 ships session tabs natively (`tabs.*` in `cli.json`).

## Session store refresh

`migrate-sessions.sh` mirrors the 1.x session store into 2.x. The two stores are
parallel — 1.x writes `session`/`message`/`part`, 2.x reads
`session_v2`/`session_message` — so a host switch otherwise shows an empty list.

| Flag            | Effect                                         |
| --------------- | ---------------------------------------------- |
| (none)          | drop migrated 1.x rows, re-copy them           |
| `--only-pinned` | touch only the pinned sessions                 |
| `--purge`       | wipe the whole 2.x store first (always total)  |
| `--backup`      | copy `opencode.db` **and `-wal`/`-shm`** aside |

Pinned sessions live outside the database, in
`~/.local/state/opencode/session.json` (`{"pinned": [...]}`) — that is the file
`--only-pinned` reads.

TUI **tabs** live in `~/.local/state/opencode/kv.json` under
`opencode-tabs:tabs:v1:<projectID>::`. They are not session data and are not
migrated: a switch shows no tabs because the 2.x project id differs, not because
the state was lost — the old entries are still in `kv.json`.

### What a 2.x message needs

The migration was rebuilt against a live host. A single message that fails to
decode makes the whole session unopenable, so every field matters:

- `model` is **required** on an assistant message; most 1.x messages carry none,
  so the session's model is the fallback.
- `variant` is omitted unless chosen — `null` fails.
- `finish` is a required enum; a 1.x message with no step-finish part has none.
- `reasoning` needs `native` and `time`; `tool` entries vary by status and are
  replayed as text instead.

Verify on a **copy** with `XDG_DATA_HOME` pointed at it, then
`opencode2 session export <id> --standalone` per session.

## Stats and prune

Both work on a 2.x host:

- **Stats** (`stats.sh` / `stats.py`) reads `session_v2` + `session_message`.
  2.x records assistant steps there and tool calls as `content` entries of
  `type == "tool"`. `session_v2` also holds 1.x rows, so the adapter filters on
  `version like '2.%'` — without it the report counts v1 sessions.
- **Prune** (`devbot prune`) resolves `opencode2` for this harness. The
  `session list --format json` payload is identical on 1.x and 2.x
  (`id`, `title`, `updated` in ms), so the shared deletion path works unchanged.

## V2 plugin API, as verified

Taken from `@opencode/plugin@2.3.0`'s own type definitions and
<https://opencode.ai/docs/build/plugins/>. The v1 adapter's six plugin keys map
like this:

| v1 key                               | v2 registration                                | notes                                                |
| ------------------------------------ | ---------------------------------------------- | ---------------------------------------------------- |
| `event` (returned)                   | `ctx.event.subscribe({ signal })`              | async iterable; abort in the cleanup `setup` returns |
| `tool.execute.before(input, output)` | `await ctx.tool.hook("execute.before", event)` | ONE mutable event                                    |
| `tool.execute.after(input, output)`  | `await ctx.tool.hook("execute.after", event)`  | discriminated on `event.status`                      |
| `chat.params(input, output)`         | `await ctx.session.hook("context", event)`     |                                                      |
| `shell.env(input, output)`           | `await ctx.shell.hook("create.before", event)` | `event.env` is mutable                               |

Tool hook event shapes (`dist/promise/tool.d.ts`):

```ts
"execute.before": {
  tool: string
  readonly sessionID: Session.ID
  readonly agent: Agent.ID
  readonly messageID: SessionMessage.ID
  readonly id: Tool.CallID
  input: unknown            // mutable; v1 called this output.args
}
"execute.after": { ...same readonly fields, input } &
  ({ status: "completed"; result: Tool.Result } | { status: "error"; error: Tool.Error })
```

`ShellCreateBefore` carries `command`, `cwd`, `timeout`, `shell`, `env`.
`ctx.location.directory` replaces v1's `directory`; `ctx.location.project`
replaces `project`; `ctx.options` replaces the plugin-options argument.

### Still to establish before porting the hooks

- The `session.hook("context")` event's agent field — v1's `chat.params` read
  `input.agent`, and the port needs the v2 equivalent before it can call
  `rememberAgent`.
- `Tool.Result`'s shape, for the `command.after` hook's exit-code and output
  checks (v1 read `output.metadata.exitCode` and `output.output`).
