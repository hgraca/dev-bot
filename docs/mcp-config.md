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

Module enablement is the primary gate:

- module **enabled** → all servers it declares are wired into _every_ harness;
- module **disabled** → its servers appear in _no_ harness config (opencode reset prunes them on reinit; claudecode regenerates without them).

Within an enabled module a server can additionally ship **wired but not started** — see [Per-server enablement](#per-server-enablement).

## Reducing the footprint

Every enabled server's tool schemas are injected into the session context, and every harness instance starts its own copy of the server process. Measured per server (2026-09-14, `tools/list` schema bytes):

| server          | tools | ~tokens of schema |
| --------------- | ----- | ----------------- |
| chrome-devtools | 29    | ~6.5k             |
| codebase-memory | 15    | ~5.9k             |
| playwright      | 21    | ~3.5k             |
| devbot-tools    | 11    | ~1.1k             |
| mdctx           | 3     | ~0.3k             |

The five heaviest or most situational servers already ship **disabled by default** — `chrome-devtools`, `playwright`, `signoz`, `jetbrains` and each `datasources-<name>` gateway — so an enabled project pays nothing for them until they are switched on ([Per-server enablement](#per-server-enablement)). To remove a server from the config entirely, **disable its module**:

```jsonc
// .devbot.project.jsonc
{ "modules": { "chrome-devtools": false, "playwright": false } }
```

Its servers then appear in no harness config (opencode reset prunes them on reinit; claudecode regenerates without them). This also drops the module's skills and tools — for the browser modules the MCP server is essentially the whole module, so the trade is usually free.

`mcp.<name>.enabled: false` in the runtime `opencode.jsonc` is a **local escape hatch** for disabling an inherited server without unregistering it. opencode reads its config once at startup (no hot-reload), so a change requires a restart.

LSP servers are the other per-instance cost — see [Harnesses](/harnesses#runtime-footprint).

## Per-server enablement

A server entry may carry `"enabled": false`. The server is still **registered** in the harness config — the flag means "wired, do not start yet" — so turning it on is a config edit, not a re-run of `devbot init`.

| Harness    | What `enabled: false` does                                                                                                                                                                                                                                                                                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| opencode   | Emitted as `mcp.<name>.enabled: false` in `opencode.jsonc` — registered but not started. Flip it to `true` (or toggle it in the harness) and restart; opencode reads its config once at startup.                                                                                                                                                                    |
| claudecode | **Ignored.** The translator drops the key and the server stays wired enabled. `.mcp.json` has no per-server on/off, and Claude Code itself ignores a `disabled`/`enabled` key in it, so writing one would only claim a state the client does not honor. Its real levers are a hard reject (`disabledMcpjsonServers`) or per-project user state (the `/mcp` toggle). |

Five servers ship disabled by default — `chrome-devtools`, `playwright`, `signoz`, the per-datasource `datasources-<name>` gateways, and `jetbrains`. On opencode that keeps ~10k tokens of tool schema and one process per server out of a session that never uses them; on Claude Code they are simply always on, the accepted cost of that harness having no per-server switch.

`enabled` is optional and defaults to **true** — a manifest that omits it is wired and started exactly as before. Declare it only to opt out. To switch one on, set its `enabled` to `true` in the generated `opencode.jsonc` entry (or toggle it in the harness) and restart.

An `enabled` value in the config is **yours**: `reinit` never reverts it. The module's declared default applies only to an entry that expresses no opinion — so a release newly declaring `enabled` still reaches an existing install, while a server you switched on stays on.

## Shared machine-wide gateways

A dev-bot MCP server must never launch its own per-instance process. Servers that are stateless and machine-global run **once per machine** as a docker compose service; every harness instance connects over streamable-http instead of spawning its own stdio copy. This follows the module-owned compose pattern (`docker-compose.yml` in the module dir, auto-discovered by `devbot up`/`down`, gated by the `modules` map).

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
| 18510 | datasources     |

The `datasources` gateway is the one gateway whose compose file is **generated**
(`storage/datasources/docker-compose.yml`) rather than shipped in its module
directory: it must receive every env var the declared datasources reference, and
those names come from the config at run time. It therefore brings its own compose
up and down from `up.sh`/`down.sh` instead of being discovered by `bin/up.sh`,
and for the same reason it uses **host networking** — so a database running on
this machine is reachable at the address the host sees. The toolbox image is
distroless, so its readiness check lives in `up.sh` rather than in a container
healthcheck. Its config holds only the sources the gateway can initialize right
now, decided once when `devbot up` runs — see `datasources` in
`docs/configuration.md`.

### Credentials

A gateway's credentials are interpolated from the **environment `devbot up` builds** — never written into a config file:

- `bin/up.sh` loads the repo-root `.env` before invoking compose. This matters because compose interpolation reads the **project directory's** `.env`, and with a module-first `-f` list (the norm — there is no root compose) that directory is the _module's_. Without the explicit load, the repo `.env` is ignored and `${VAR}` silently interpolates to empty.
- Put the value in the repo-root `.env`, or export it in the shell that runs `devbot up`.

Changing a credential needs a container recreate — `devbot up` runs compose with `--no-recreate`.

A missing credential is **not** reliably visible to a readiness probe: an MCP `initialize` handshake succeeds against a gateway with no working credential. So `signoz/up.sh` reports `DEGRADED` rather than `reachable` when `SIGNOZ_AUTH_TOKEN` is unset.

### Lifecycle and health

Gateways are started on demand by `devbot up` and left running. They use `restart: "no"` **deliberately** rather than `unless-stopped`: a gateway is a dev-machine service tied to the dev-bot services around it, so it should not come back on its own after a reboot without `devbot up` having started its neighbours.

A gateway whose image is **built** from a module `Dockerfile` is rebuilt when that build input changes: `devbot up` runs a cache-warm build for each selected module that builds its own image and recreates the container only when the resulting image id actually changed. A module that merely references a published image (signoz) is not built.

Each gateway declares a healthcheck that performs a real MCP handshake on its own port, so `docker ps` reports a gateway that has stopped answering as `unhealthy`. The probe runs `python3` — the bridge images install it for `mcp-proxy` and carry no HTTP client.

`signoz` is the exception: its official image is **distroless** (no shell, and none of `curl`/`wget`/`python3`/`node`), so nothing can run a probe inside it. Its readiness is covered by `signoz/up.sh` instead, which handshakes over the network and reports `DEGRADED` when the API token is missing. The compose file states this rather than leaving it implicit.

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

| Field     | Required | Meaning                                                                                                                                                                            |
| --------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `type`    | yes      | Transport: `stdio` (spawn a local command) or `http` (remote endpoint).                                                                                                            |
| `command` | stdio    | Uniform argv array launching the server (claudecode splits `argv[0]`/`args`).                                                                                                      |
| `url`     | http     | Remote MCP endpoint.                                                                                                                                                               |
| `oauth`   | http     | Optional `false` to disable opencode's automatic OAuth detection.                                                                                                                  |
| `enabled` | no       | `false` ships the server **wired but not started**. Honored by opencode only — claudecode drops the key (see [Per-server enablement](#per-server-enablement)). Defaults to `true`. |
| `env`     | no       | Environment for the server process — single source of truth for both harnesses.                                                                                                    |

Any other key (e.g. a leftover `environment` or `headers`) fails translation loudly — a migration safety net. Keys starting with `_` are ignored (annotation convention, as in `hooks.json`).

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
| `enabled` | carried when declared                 | dropped — no equivalent field       |

The canonical `env` block is renamed per harness (`environment` for opencode, `env` for claudecode); placeholders resolve at registration except when comparing templates (below). `enabled` is carried to opencode and dropped for claudecode, whose entry shape has no equivalent field.

### Registration

- **opencode** (`bin/init.sh:_register_module_mcp`) — translates each enabled module's manifest (resolving `__GPU_ENABLED__`/`__DEV_BOT_ROOT__`), then merges each server into `opencode.jsonc` with `merge_mcp_jsonc.py`. Merge is skip-if-exists, so local/user edits to an `opencode.jsonc` MCP entry survive reinit — except entries of the modules on reset's explicit refresh list (see below), which are refreshed when stale.- **claudecode** (`src/harnesses/claudecode/init.sh:_wire_mcp`) — translates each enabled module's manifest, resolves `__GPU_ENABLED__`/`__DEV_BOT_ROOT__`, merges into a temp map, validates transport types (an invalid `type` would make Claude Code reject the whole `.mcp.json`), and writes `.mcp.json` from scratch. Dynamic runtime manifests (`.claude/*.mcp.json`, e.g. jetbrains' port) merge the same way.

### Reset / reinit

`src/_shared/mcp_key_is_current.py` compares a registered entry against its module's canonical manifest _translated to that harness_ and reports stale entries, so `reset.sh` drops only what init would re-register differently — keeping reinit byte-idempotent (audit-32). The opencode refresh is scoped to an **explicit list** of modules whose canonical manifest changed (`codebase-memory`, `mdctx`, `signoz`, `svelte`, `tools-mcp`, `playwright`, `chrome-devtools` — add a module here when a release changes its `mcp.json`); every other module's entry is user-owned and never dropped by reset, only pruned when its module is disabled. A refreshed entry that was not the last key in the `mcp` map is re-appended at the end, so the reinit that refreshes it reorders keys once; the re-registered entry then matches, so later reinits are no-ops. A module that **drops** its MCP server entirely is additionally pruned by reset's retired-key list (`RETIRED_MCP_KEYS`), since its canonical manifest is gone and the other prune paths are keyed on it — qmd's `qmd mcp` server is retired this way. It normalizes the machine-dependent placeholders before comparing:

- `__GPU_ENABLED__` — with `--gpu` supplied (both resets pass `_qmd_gpu_value()`, the same source init resolves the placeholder with), the config value must equal that host value or the entry is stale, so a stale/wrong GPU value self-heals; without `--gpu`, any resolved string is current (GPU value is machine-dependent);
- `__DEV_BOT_ROOT__` — the suffix after the placeholder must still match (root layout drift is stale);
- `{env:VAR}` — current whether the config holds the native token literal (opencode `{env:VAR}`, claudecode `${VAR}`) or omits the key.

### Inventory

`devbot list mcps` / `devbot list mcps -a` reads the canonical manifests (see [MCPs](/mcps) for the generated inventory).

## Special cases

- **codebase-index — plugin-provided on opencode.** opencode integrates it via `plugin.opencode.json` (the plugin spawns the server), so the opencode registration adapter skips modules that declare a plugin manifest — registering the server as an MCP too would double-load it. Its canonical `mcp.json` (using `{harness-dir}` + `--host {host}`) serves claudecode.
- **Dynamic runtime manifests** (`.opencode/*.mcp.json`, `.claude/*.mcp.json` written by module inits for values only known at runtime, e.g. jetbrains' IDE port) stay harness-native. opencode registration **upserts**: a def that differs from the registered entry replaces it, so a release can change what a module emits (e.g. flipping `enabled`) and existing configs pick it up on reinit — while a def that already matches is left untouched, keeping reinit byte-idempotent.
- **Dynamic manifests on claudecode** — `_wire_mcp` reads `enabled` on a dynamic entry as a wire/don't-wire gate, so a module that ships its opencode manifest disabled keeps `enabled: true` in the claude one: `.mcp.json` cannot carry the state, and `false` there would silently drop the server.
- **Docker-only servers** — skipped when no docker daemon is available. A hybrid definition (docker plus a non-docker fallback its own launcher picks — playwright) is kept: it declares `"_hybrid": true` in its canonical manifest, which is what the guard reads, never the fallback's command text.

## Harness differences

- **opencode** — merge-only registration preserves local config edits; entries of the explicit refresh-list modules and of disabled modules are pruned by `reset.sh` (byte-idempotent). `opencode.jsonc` is gitignored.
- **claudecode** — `.mcp.json` is regenerated from scratch on every init (also gitignored, so nothing dev-bot-managed is ever committed); edit the module's canonical `mcp.json` to change defaults, since per-project `.mcp.json` edits are overwritten on reinit.

> **Consumer projects**: gitignore the dotfile — a bare `mcp.json` rule (common in `###> ai ###` blocks) does **not** match `.mcp.json`. Update it to `.mcp.json` so a regenerated claudecode config is never committed.
