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
this one refuses a 1.x host (`_devbot_require_opencode_2x`). The two lines run
side by side: `opencode` launches 1.x from `~/.opencode/bin/opencode`, `opencode2`
launches 2.x from `~/.opencode/v2/opencode`.

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

- **A configured local plugin path only resolves under `.opencode/plugins/`.**
  Entries pointing anywhere else — `./.opencode/v2/plugins/x`,
  `.opencode/v2/plugins/x` — are skipped **silently**, with no log line.
- **A symlinked plugin entry is skipped too.** The entry must be a real file, so
  `init.sh` writes a small shim that re-exports the module's own source:
  `export { default } from "<DEV_BOT_ROOT>/src/harnesses/opencode-v2/hooks/x.ts"`.
  `import.meta.dir` inside the real module still resolves to the module, so
  there is one source of truth.

Both harnesses therefore share `.opencode/plugins/`, and isolation comes from a
handover sweep rather than from separate directories:

- v1 writes `*.ts` files there; v2 writes `<name>/index.ts` directories.
- On init, v2 removes every symlink under `.opencode/` that resolves under
  `DEV_BOT_ROOT`, so a deselected v1 adapter's plugins cannot be auto-loaded.
- User files and `.opencode/opencode.json` are never touched.

V1's `reset.sh` exits when it is not the selected harness by design, so the
incoming harness does the cleaning.

## Version support

`_devbot_require_opencode_2x` reads `opencode2 --version` and refuses the 1.x
line. It fails open on a missing binary and on an unparseable version, and
allows a source build reporting `0.0.0--<timestamp>`.

## Config migration

Both harnesses read the **same** `opencode.jsonc`, so a project that once ran
the v1 adapter already has a v1 document. `init.sh` converts it once, through
`lib/migrate_v1.py`, and leaves `opencode.jsonc.pre-v2.bak` beside it:

| v1 | v2 |
| --- | --- |
| `plugin` (strings and `[name, options]` tuples) | `plugins` (strings, or `{package, options}`) |
| `permission` (object per tool) | `permissions` (ordered rules, last match wins) |
| `agent` (`prompt`, `disable`, `variant`) | `agents` (`system`, `disabled`, `model#variant`) |
| `provider` (`npm`, `options`) | `providers` (`package`, `settings`) |
| `mcp.<name>` with `enabled` | `mcp.servers.<name>` with `disabled` (inverted) |
| `lsp` | dropped — v2 runs no language servers |

Permission keys with no v2 action are dropped rather than mistranslated:
`list`, `todowrite`, `todoread`, `codesearch`, `doom_loop`, `lsp`.

## Agent PTY

v1 pinned `opencode-pty@0.3.6`. Its published builds still depend on
`@opencode-ai/plugin ^1.3.13`, and V1 plugin implementations do not run on a V2
host, so there is no upstream build to pin. `hooks/pty.ts` provides the five
tools (`pty_spawn`, `pty_write`, `pty_read`, `pty_list`, `pty_kill`) directly via
`ctx.tool.transform`, backed by `bun-pty` (declared in the scaffold's
`package.json`). If `bun-pty` cannot be resolved the tools still register and
return an actionable message rather than vanishing from the toolset.

## TUI parts (not yet ported)

V2 keeps TUI plugins, but as a **part of a plugin package**, not a separate
project-local `tui.json`:

- A package declares `exports["./tui"]`; its default export is
  `{ id?, tui }` where `tui = async (api, options, meta) => …` — a different
  shape from the server part's `Plugin.define`.
- **Plugins listed in `opencode.jsonc` that expose a `./tui` part are loaded
  automatically by the CLI.** The global `~/.config/opencode/cli.json` is only
  for CLI-only plugins, so this harness never needs to write outside the
  project.
- A local plugin directory resolves parts through its `package.json` `exports`,
  or bare `server`/`tui` files at its root.

The three v1 TUI plugins (`pty-monitor`, `tui-defaults`, `provider-ttft`) are
not ported yet. Their sources use the V1 TUI primitives
(`api.tuiConfig`, per-project `tui.json` slots), so this is a component rewrite
against `@opencode/plugin/tui`, not a file move.

## Known gaps

- TUI parts are not ported (see above); the harness is server-side only.
- Module hooks declared with a `plugin:` factory in `hooks.json` are V1 plugin
  implementations. The adapter logs their ids at startup and does not wire them.
- The `shell` hook carries no session id, so the session env attach follows the
  most recent session that ran a model request.
- `devbot prune` still targets the v1 host only: it drives
  `opencode session list --format json`, and the 2.x CLI's equivalent is not
  confirmed. The SQLite `session_v2` pruning helper itself is harness-agnostic.
- Stats: `devbot stats` looks for `src/harnesses/<harness>/stats.sh`, which this
  module does not ship yet, so it reports the harness as unsupported.

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
