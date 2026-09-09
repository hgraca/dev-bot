---
layout: page
title: MCP configuration
description: Canonical per-module MCP manifests and how each harness wires them.
nav_section: docs
---

# MCP configuration

Each module declares its MCP servers **once** in a **`mcp.json` manifest** (harness-agnostic), and each harness wires it into its own runtime config through a **single shared translator** — the same architecture as the [Hooks](/hooks) manifests:

- **Translation** — `src/_shared/mcp_translate.py` maps a canonical manifest to a harness shape. No consumer re-implements the mapping, so per-harness drift (the old `mcp.opencode.json` / `mcp.claudecode.json` pair suffered exactly that) cannot reappear.
- **OpenCode** — `bin/init.sh` translates and merges each manifest into the `mcp` block of `opencode.jsonc`; `opencode/reset.sh` prunes stale and disabled-module entries.
- **Claude Code** — the claudecode harness `_wire_mcp` translates and regenerates `.mcp.json` from scratch.

## Module gate

There is **no per-server `enabled` field** and no per-harness enablement. Module enablement is the only gate:

- module **enabled** → all servers it declares are wired into _every_ harness;
- module **disabled** → its servers appear in _no_ harness config (opencode reset prunes them on reinit; claudecode regenerates without them).

## Canonical manifest

`src/agentic/<module>/mcp.json`:

```json
{
    "mcp": {
        "qmd": {
            "type": "stdio",
            "command": ["bash", "-c", "mkdir -p .agents/logs && exec qmd mcp 2>>.agents/logs/qmd-mcp.log"],
            "env": {
                "QMD_LLAMA_GPU": "__GPU_ENABLED__",
                "QMD_EXPAND_CONTEXT_SIZE": "512"
            }
        },
        "context7": {
            "type": "http",
            "url": "https://mcp.context7.com/mcp",
            "oauth": false
        }
    }
}
```

| Field     | Required | Meaning                                                                         |
| --------- | -------- | ------------------------------------------------------------------------------- |
| `type`    | yes      | Transport: `stdio` (spawn a local command) or `http` (remote endpoint).         |
| `command` | stdio    | Uniform argv array launching the server (claudecode splits `argv[0]`/`args`).   |
| `url`     | http     | Remote MCP endpoint.                                                            |
| `oauth`   | http     | Optional `false` to disable opencode's automatic OAuth detection.               |
| `env`     | no       | Environment for the server process — single source of truth for both harnesses. |

Any other key (e.g. a leftover `enabled` or `environment`) fails translation loudly — a migration safety net. Keys starting with `_` are ignored (annotation convention, as in `hooks.json`).

## Tokens and placeholders

Resolved at translation time by `mcp_translate.py`:

| Token              | Resolves to                                       | Used by                                                  |
| ------------------ | ------------------------------------------------- | -------------------------------------------------------- |
| `{harness-dir}`    | `.opencode` \| `.claude`                          | wrapper/serve-script paths in commands                   |
| `{host}`           | `opencode` \| `claude` (product name)             | servers with a `--host` config selector (codebase-index) |
| `__GPU_ENABLED__`  | `metal`\|`cuda`\|`vulkan`\|`false` (registration) | qmd GPU selection                                        |
| `__DEV_BOT_ROOT__` | the dev-bot install root (registration)           | mdctx index paths                                        |
| `{env:VAR}`        | see below                                         | secrets / per-machine config                             |

`{env:VAR}` is an env indirection resolved by **each client natively at launch** — the shared translator maps it to the harness's native spelling, so the value is never resolved into a config file:

- **opencode** keeps `{env:VAR}` in `opencode.jsonc` — opencode interpolates it at launch from its own process env.
- **claudecode** `.mcp.json` carries `${VAR}` — Claude Code's native expansion (the claudecode target cannot use `{env:VAR}`, and Claude Code expands `${VAR}` in `env`, `command`, `args`, `url` and `headers`). A missing variable (no `${VAR:-default}`) loads the config with a warning and registers the unexpanded text.

`{env:VAR}` is whole-value-only (it must be the entire env value, never embedded in a URL or path) — the translator rejects malformed or embedded tokens so both harnesses cannot silently diverge.

## Interpretation per harness

`mcp_translate.py` output shapes:

| Canonical | opencode                              | claudecode                          |
| --------- | ------------------------------------- | ----------------------------------- |
| `stdio`   | `{type: local, command, environment}` | `{type: stdio, command, args, env}` |
| `http`    | `{type: remote, url, oauth?}`         | `{type: http, url, env?}`           |

The canonical `env` block is renamed per harness (`environment` for opencode, `env` for claudecode); placeholders resolve at registration except when comparing templates (below).

### Registration

- **opencode** (`bin/init.sh:_register_module_mcp`) — translates each enabled module's manifest (resolving `__GPU_ENABLED__`/`__DEV_BOT_ROOT__`), then merges each server into `opencode.jsonc` with `merge_mcp_jsonc.py`. Merge is skip-if-exists, so local/user edits to an `opencode.jsonc` MCP entry survive reinit — except entries of the modules on reset's explicit refresh list (see below), which are refreshed when stale.- **claudecode** (`src/harnesses/claudecode/init.sh:_wire_mcp`) — translates each enabled module's manifest, resolves `__GPU_ENABLED__`/`__DEV_BOT_ROOT__`, merges into a temp map, validates transport types (an invalid `type` would make Claude Code reject the whole `.mcp.json`), and writes `.mcp.json` from scratch. Dynamic runtime manifests (`.claude/*.mcp.json`, e.g. jetbrains' port) merge the same way.

### Reset / reinit

`src/_shared/mcp_key_is_current.py` compares a registered entry against its module's canonical manifest _translated to that harness_ and reports stale entries, so `reset.sh` drops only what init would re-register differently — keeping reinit byte-idempotent (audit-32). The opencode refresh is scoped to an **explicit list** of modules whose canonical manifest changed (`qmd`, `mdctx`, `tools-mcp` — add a module here when a release changes its `mcp.json`); every other module's entry is user-owned and never dropped by reset, only pruned when its module is disabled. It compares placeholder-insensitively:

- `__GPU_ENABLED__` — any resolved string is current (GPU value is machine-dependent);
- `__DEV_BOT_ROOT__` — the suffix after the placeholder must still match (root layout drift is stale);
- `{env:VAR}` — current whether the config holds the native token literal (opencode `{env:VAR}`, claudecode `${VAR}`) or omits the key.

### Inventory

`devbot list mcps` / `devbot list mcps -a` reads the canonical manifests (see [MCPs](/mcps) for the generated inventory).

## Special cases

- **codebase-index — plugin-provided on opencode.** opencode integrates it via `plugin.opencode.json` (the plugin spawns the server), so the opencode registration adapter skips modules that declare a plugin manifest — registering the server as an MCP too would double-load it. Its canonical `mcp.json` (using `{harness-dir}` + `--host {host}`) serves claudecode.
- **Dynamic runtime manifests** (`.opencode/*.mcp.json`, `.claude/*.mcp.json` written by module inits for values only known at runtime, e.g. jetbrains' IDE port) stay harness-native and are unchanged.
- **Docker-only servers** — skipped when no docker daemon is available; hybrid definitions with an `npx` fallback (playwright) are kept (their wrapper picks the path).

## Harness differences

- **opencode** — merge-only registration preserves local config edits; entries of the explicit refresh-list modules and of disabled modules are pruned by `reset.sh` (byte-idempotent). `opencode.jsonc` is gitignored.
- **claudecode** — `.mcp.json` is regenerated from scratch on every init (also gitignored, so nothing dev-bot-managed is ever committed); edit the module's canonical `mcp.json` to change defaults, since per-project `.mcp.json` edits are overwritten on reinit.
