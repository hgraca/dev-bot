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

| Concern | v1 | v2 |
| --- | --- | --- |
| Config file | `opencode.jsonc`, `tui.json` | `opencode.jsonc` (same name, new key shapes) |
| Hooks | V1 object returned from the plugin function | `Plugin.define` + per-domain `hook()` |
| Plugins key | `plugin: [...]` | `plugins: [{ package, options }]` |
| MCP key | `mcp: { <name>: { enabled } }` | `mcp.servers: { <name>: { disabled } }` |
| Permissions | `permission` object | `permissions` ordered array, last match wins |
| Agents | `agent` map (`prompt`, `disable`) | `agents` map (`system`, `disabled`) |
| Providers | `provider` (`npm`) | `providers` (`package`, `aisdk:` prefix) |
| TUI parts | project `tui.json` + `.opencode/tui-plugins/` | plugin package `exports["./tui"]` |
| Instruction file | `AGENTS.md`, `CLAUDE.md` fallback | `AGENTS.md` only |

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

The two harnesses never share a plugin directory, because v1's `reset.sh` exits
when it is not the selected harness and a deselected harness's symlinks would
otherwise survive:

- v1 owns `.opencode/plugins/` and `.opencode/tui-plugins/`.
- v2 owns `.opencode/v2/plugins/`, registered explicitly in `plugins` so nothing
  depends on auto-discovery.

On handover, `init.sh` prunes only symlinks resolving under `DEV_BOT_ROOT` and
removes `plugins/`/`tui-plugins/` once empty. User-created files and
`.opencode/opencode.json` are left alone — reinit must never destroy a setup it
does not manage.

## Version support

`_devbot_require_opencode_2x` reads `opencode2 --version` and refuses the 1.x
line. It fails open on a missing binary and on an unparseable version, and
allows a source build reporting `0.0.0--<timestamp>`.
