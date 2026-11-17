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
- On init, v1 retires the `<name>/` directories whose `index.ts` carries the
  v2 shim marker (`_sweep_v2_plugin_dirs`). Retiring the `pty` package also drops
  `bun-pty` from `.opencode/package.json`, but only when it is named in
  `.opencode/.devbot-managed-deps` — the record this harness writes when it seeds
  that manifest, so a dependency the project declared itself is never touched.
- User files and `.opencode/opencode.json` are never touched; the manifest edit
  above is the single exception, and it is keyed on the v2 package being gone.

V1's `reset.sh` exits when it is not the selected harness by design, so the
incoming harness does the cleaning.

A package carries its parts as siblings: `index.ts` is the server entry, and
`tui.ts` / `rpc.ts` are linked only when they exist, because the host rejects a
package whose `exports` names a file that is not there. `hooks/pty/` is the only
such package today, and its manifest is the only one with `./tui` and `./rpc`
exports.

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
host, so there is no upstream build to pin. `hooks/pty/` provides the five tools
(`pty_spawn`, `pty_write`, `pty_read`, `pty_list`, `pty_kill`) directly via
`ctx.tool.transform`, backed by `bun-pty`, which `init.sh` installs with
`bun install` (~2s). The scaffold declares **only** bun-pty: `@opencode/plugin`
is resolved by the host at runtime, and listing it pulls its full dependency
graph on every install for no benefit. The plugin also resolves bun-pty from the
project's `.opencode/node_modules` as a fallback, because the re-export shim
makes a bare specifier resolve against the dev-bot checkout instead. If it
cannot be resolved the tools still register and return an actionable message
rather than vanishing from the toolset.

Verified end to end on a 2.3.0 host: spawn → read (`hello-from-pty`, exit 0) →
kill. A tool result carrying `output` must declare an output schema — without
one the whole result fails to serialise and the model retries, so these tools
return content only.

### The PTY extension owns three parts

`hooks/pty/` is a plugin package, not a hook file:

| File          | Part   | What it does                                                      |
| ------------- | ------ | ----------------------------------------------------------------- |
| `index.ts`    | server | The five tools, the session registry, registers `PtyRpc`          |
| `tui.ts`      | TUI    | The sidebar block and the session panel                           |
| `rpc.ts`      | RPC    | The contract both halves import: session info shape, method list  |
| `lib.ts`      | —      | Pure helpers (info shape, row text, tail, pagination) + its tests |
| `sessions.ts` | —      | The registry: spawn, buffer, read, write, kill + its tests        |

**The session info carries `parentSessionId`.** `execute(input, context)` gives
the spawning agent session in `context.sessionID`, so `pty_list` and the RPC can
attribute a session and filter by it — the field proposed upstream in
[shekohex/opencode-pty#91](https://github.com/shekohex/opencode-pty/pull/91).
The published shape otherwise mirrors the v1 monitor's (`title`, `command`,
`workdir`, `status`, `pid`, `exitCode`, `createdAt`, `exitAt`, `lineCount`), with
`status` derived rather than stored: `running` until the exit callback stamps a
time, then `killed` if we stopped it and `exited` otherwise. There is no `args`:
the tools take one command line, and splitting it back into argv would invent a
shape the session never had.

**The RPC is the only channel between the parts.** They run in different
processes and share no memory; v1's monitor scraped an HTTP port the plugin
posted into the transcript, and v2 has no such surface. `index.ts` registers
`PtyRpc` with `ctx.rpc.register`, `tui.ts` calls it through `ctx.client.rpc`.
The contract is four methods: `list` (sessions, optionally filtered by the
spawning session), `read` (a tail of a session's output), `write` (raw input for
a session — what the panel's send controls use) and `kill` (stop a session and
optionally drop its record — what the dismissal controls call).
`rpc.ts` deliberately imports nothing: the TUI process provides
`@opencode/plugin/tui` to a plugin module and no other `@opencode/*` specifier,
so a schema helper imported there would fail to resolve. A plain JSON Schema
object is a valid RPC definition, so the contract needs no import at all.

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

**Shipped:** the PTY monitor, as the `./tui` part of the `hooks/pty/` package.

It is the v1 `pty-monitor` experience re-earned on 2.3:

- **Sidebar.** A `sidebar.content` block lists the PTY sessions the agent
  session in view spawned, one row each: a bullet tinted green while running, red
  on a non-zero exit, muted otherwise; the title or command; and the live line
  count, exit code or status. "Spawned by" means the whole family, not just that
  session id: a subagent's PTY carries the subagent's `parentSessionId`, and
  `ctx.data.session.family()` is what keeps those rows visible. A header counts
  them and reads `PTY unavailable` when the RPC call fails. No sessions means no
  block at all, so an idle session pays no line for it.
- **Panel.** Clicking a row opens the output in the `session.panel` slot, not a
  dialog or a route: the session view stays put, and the host owns the panel's
  layout, focus and fullscreen toggle. The panel header carries id, status, pid,
  line count and elapsed time, then the command and its workdir; the body is a
  bottom-pinned scrollbox over the last 300 lines the RPC returns, refreshed once
  a second.

Both halves poll: the list every 2s, the open panel's output every 1s.

**The panel can answer a session.** A process that stops at `[y/N]`, at
`Continue?`, or at a REPL prompt is not stuck:

- `[send]` in the panel footer (or `ctrl+s`) opens the host's prompt dialog; the
  line is sent with a carriage return, which is what a terminal's Enter is;
- `[keys]` sends what a text field cannot: Escape, Tab, `Ctrl+C`, `Ctrl+D`, and
  the four arrows. `Ctrl+C` here interrupts the **child**, not the agent — that
  is the point of sending it as a key rather than binding it;
- the prompt itself is visible before it is answered, because the buffer's
  unterminated tail is part of what the panel reads. A `Password: ` never ends
  with a newline, and hiding it would leave an empty view of a session that is
  waiting for you;
- nothing is echoed locally: the child's own echo arrives through the output
  stream, so the panel never invents characters. When the child turns echo off,
  the answer is not echoed at all — the panel shows the prompt, then whatever the
  child prints next.

**A secret does not belong in the send dialog.** The host's prompt renders what
you type and has no masked mode, so a password would be visible on screen while
you type it. Feed secrets to the child through its environment or a credentials
helper (`GIT_ASKPASS` is the usual one) and keep the send dialog for answers that
are safe to see. That prompt is also what makes `Password: ` answerable at all;
it simply cannot hide the answer too.

This is **line mode, not a terminal emulator**. Answering a prompt, sending
`y`, interrupting a run and typing into a REPL all work; driving a full-screen
program (`vim`, `less`, `htop`) does not — those need raw keystrokes and screen
state, which this panel cannot emulate. Use the host's own terminal pane for
that.

**Dismissal works from the sidebar**, as it did in v1 — the agent's `pty_kill`
tool is not something the user at the keyboard can reach:

- a `✕` on each row removes that session; a **running** one is confirmed first,
  because removing it kills a live process, while a finished one is only a record
  and goes at once;
- `(clear finished)` in the block header drops every stopped session the block
  shows. It is rendered only when something can be cleared, so it never offers to
  delete nothing, and it never touches a live session;
- a removal is a **cleanup**: the record and its buffer go, which is exactly what
  `pty_kill cleanup=true` does. Removing the row the panel is showing closes the
  panel rather than leaving it on an empty id.

Underneath, the registry still bounds itself: the twenty finished sessions that
stopped most recently are kept and the rest are dropped automatically, so a
session nobody dismisses cannot grow the process the way `opencode-pty`'s list
did.

**Verified on a 2.3.0 host:** the package's three parts load (the host logs no
failed plugin), the block renders in `sidebar.content` after the built-in MCP
block, and its header reads `PTY` rather than `PTY unavailable` — which is the
RPC round-trip from the TUI process succeeding. Clicking a row and the panel's
scroll behaviour need a live session and a human at the keyboard; they are the
one part of this module no test covers.

**Retired:** `provider-ttft` — ported once, then dropped: 2.3's built-in
`opencode.prompt.footer` already renders `· 1.2 ttft` (and `tok/s`), both gated
by the `session.tps` CLI setting, so a second copy in the sidebar was noise.
`init.sh` retires the package an earlier build linked.

**Not ported:** `tui-defaults`. It was written against the pre-2.3 API
(`kv`/`slots`/`events`), which 2.3 no longer exposes, so linking it only produced
`Invalid V2 TUI plugin module` on every start. Its only job is seeding the
tool-details kv default, and 2.3 has no plugin-facing kv surface to seed.

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
