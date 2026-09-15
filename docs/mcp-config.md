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

## Reducing the footprint

Every enabled server's tool schemas are injected into the session context, and every harness instance starts its own copy of the server process. Measured per server (2026-09-14, `tools/list` schema bytes):

| server          | tools | ~tokens of schema |
| --------------- | ----- | ----------------- |
| chrome-devtools | 29    | ~6.5k             |
| codebase-memory | 15    | ~5.9k             |
| playwright      | 21    | ~3.5k             |
| devbot-tools    | 11    | ~1.1k             |
| mdctx           | 3     | ~0.3k             |

To stop paying for a server in a project, **disable its module** — module enablement is the only gate:

```jsonc
// .devbot.project.jsonc
{ "disabled_modules": ["chrome-devtools", "playwright"] }
```

Its servers then appear in no harness config (opencode reset prunes them on reinit; claudecode regenerates without them). This also drops the module's skills and tools — for the browser modules the MCP server is essentially the whole module, so the trade is usually free.

`mcp.<name>.enabled: false` in the runtime `opencode.jsonc` is a **local escape hatch** for disabling an inherited server without unregistering it. opencode reads its config once at startup (no hot-reload), so a change requires a restart.

LSP servers are the other per-instance cost — see [Harnesses](/harnesses#runtime-footprint).

## Shared machine-wide gateways

A dev-bot MCP server must never launch its own per-instance process. Servers that are stateless and machine-global run **once per machine** as a docker compose service; every harness instance connects over streamable-http instead of spawning its own stdio copy. This follows the module-owned compose pattern (`docker-compose.yml` in the module dir, auto-discovered by `devbot up`/`down`, gated by `disabled_modules`).

The canonical manifest declares such a server as `http`:

```json
{ "mcp": { "mdctx": { "type": "http", "url": "http://127.0.0.1:18501/mcp" } } }
```

The translator maps `http` to opencode's `remote` and Claude Code's `http` — no per-harness wiring.

### Port registry

Gateways bind `127.0.0.1` only (never exposed off the machine), in the `18500–18599` block:

| port  | server          |
| ----- | --------------- |
| 18501 | mdctx           |
| 18502 | signoz          |
| 18503 | svelte          |
| 18504 | codebase-memory |

### Credentials

A gateway's credentials are interpolated from the **environment `devbot up` builds** — never written into a config file:

- `bin/up.sh` loads the repo-root `.env` before invoking compose. This matters because compose interpolation reads the **project directory's** `.env`, and with a module-first `-f` list (the norm — there is no root compose) that directory is the _module's_. Without the explicit load, the repo `.env` is ignored and `${VAR}` silently interpolates to empty.
- Put the value in the repo-root `.env`, or export it in the shell that runs `devbot up`.

Changing a credential needs a container recreate — `devbot up` runs compose with `--no-recreate`.

A missing credential is **not** reliably visible to a readiness probe: an MCP `initialize` handshake succeeds against a gateway with no working credential. So `signoz/up.sh` reports `DEGRADED` rather than `reachable` when `SIGNOZ_AUTH_TOKEN` is unset.

### stdio servers behind a bridge

A server that only speaks stdio runs behind `mcp-proxy` inside its container, which exposes streamable-http at `/mcp`:

```dockerfile
CMD ["mcp-proxy", "--port=18501", "--host=0.0.0.0", "--", "mdctx-mcp"]
```

`--host=0.0.0.0` is required inside the container so the host port mapping can reach it. Pin `mcp-proxy` together with `mcp<2` — 0.12.0 is incompatible with the 2.x SDK.

If the container is not running the server is simply unavailable; there is no stdio fallback (that would reintroduce the per-instance process).

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
| `__GPU_ENABLED__`  | `metal`\|`cuda`\|`vulkan`\|`false` (registration) | reserved — no shipped module uses it                     |
| `__DEV_BOT_ROOT__` | the dev-bot install root (registration)           | mdctx index paths                                        |
| `{env:VAR}`        | see below                                         | secrets / per-machine config                             |

`{env:VAR}` is an env indirection resolved by **each client natively at launch** — the shared translator maps it to the harness's native spelling, so the value is never resolved into a config file:

- **opencode** keeps `{env:VAR}` in `opencode.jsonc` — opencode interpolates it at launch from its own process env.
- **claudecode** `.mcp.json` carries `${VAR}` — Claude Code's native expansion (the claudecode target cannot use `{env:VAR}`, and Claude Code expands `${VAR}` in `env`, `command`, `args`, `url` and `headers`). A missing variable (no `${VAR:-default}`) loads the config with a warning and registers the unexpanded text.

`{env:VAR}` is whole-value-only (it must be the entire env value, never embedded in a URL or path) — the translator rejects malformed or embedded tokens so both harnesses cannot silently diverge.

### Env-var presence check (init / harness start)

Because the client resolves `{env:VAR}` at launch, a missing variable only surfaces when the server fails to start — long after init wrote the config. `src/_shared/mcp_env_refs.py` + the `_devbot_*_mcp_env_vars` helpers in `src/_shared/functions.sh` close that gap by checking, against the current shell env, every `{env:VAR}` referenced by the canonical manifests of **enabled** modules (plugin-provided and disabled modules are skipped, mirroring the registration skip set):

- **`devbot init` / single-project `reinit`** — after MCP registration, if any referenced var is unset/empty, init prints the notice (var + module/server + `export VAR=…` in `~/.bashrc`) and waits for a **press-any-key acknowledgement** before continuing.
- **`devbot reinit --all`** — each per-project init emits only a compact notice (`DEV_BOT_DEFER_ENV_DIALOG=1` defers the dialog); after all projects are processed, reinit shows **one** full notice for the union of missing vars across projects.
- **`devbot` (harness `start.sh`, opencode + claudecode)** — before launching, the same check asks **"Launch the harness anyway? [y/N]"**; answering No aborts the launch.
- **Non-interactive** runs (`SKIP_CONFIRM=1` or no TTY) print the notice but never block.

The notice tells the user to add the vars to their shell profile (`~/.bashrc` or equivalent) and start devbot from a **new terminal** — the running process cannot pick up vars added after it started. The check only tests presence; values are never resolved or written to any config (secrets stay out of configs, per the design above).

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

`src/_shared/mcp_key_is_current.py` compares a registered entry against its module's canonical manifest _translated to that harness_ and reports stale entries, so `reset.sh` drops only what init would re-register differently — keeping reinit byte-idempotent (audit-32). The opencode refresh is scoped to an **explicit list** of modules whose canonical manifest changed (`mdctx`, `tools-mcp` — add a module here when a release changes its `mcp.json`); every other module's entry is user-owned and never dropped by reset, only pruned when its module is disabled. A module that **drops** its MCP server entirely is additionally pruned by reset's retired-key list (`RETIRED_MCP_KEYS`), since its canonical manifest is gone and the other prune paths are keyed on it — qmd's `qmd mcp` server is retired this way. It normalizes the machine-dependent placeholders before comparing:

- `__GPU_ENABLED__` — with `--gpu` supplied (both resets pass `_qmd_gpu_value()`, the same source init resolves the placeholder with), the config value must equal that host value or the entry is stale, so a stale/wrong GPU value self-heals; without `--gpu`, any resolved string is current (GPU value is machine-dependent);
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

> **Consumer projects**: gitignore the dotfile — a bare `mcp.json` rule (common in `###> ai ###` blocks) does **not** match `.mcp.json`. Update it to `.mcp.json` so a regenerated claudecode config is never committed.
