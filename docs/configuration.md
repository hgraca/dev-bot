---
layout: page
title: Configuration
description: devbot.jsonc — project and global configuration.
nav_section: docs
---

# devbot.jsonc

Configuration file for dev-bot agent projects. JSONC format — supports `//` comments and trailing commas.

Two files exist at different scopes, both optional:

## Locations

| File                                 | Scope           | Purpose                             | Created by     |
| ------------------------------------ | --------------- | ----------------------------------- | -------------- |
| `<project>/.devbot.project.jsonc`    | **Per-project** | Project-specific settings           | `devbot init`  |
| `<devbot-root>/.devbot.global.jsonc` | **Global**      | Shared defaults across all projects | `make install` |

## Resolution

Scalar settings resolve project-over-global, falling back to a built-in default when neither is set (`devbot_dir`, `harness`). Map settings (`modules`) merge per key, the project value winning; list settings (`devbot:guards`) are concatenated and evaluated first-match-wins (project rules first, then global). `search-memories` reads only the project config. If a file is missing, its settings are skipped.

### Auto-reinit on config change

Both config files are the source of truth for wiring — changing one (e.g. a `modules` flip, a provider key, `gpu_enabled`) only takes effect after a reinit. Rather than requiring a manual `devbot reinit`, the next **bare `devbot` start** detects the change and reinits the current project automatically, **before** `up.sh` runs, so the whole start sequence runs on freshly wired state.

Detection is a single per-project content hash over **both** configs, stored at `<project>/.devbot.project.sha` (the project config path with its `.jsonc` extension **replaced** — never committed). `init`/`reinit` clear the baseline _before_ touching the wiring and restore it at the end of a successful run, so an unchanged wiring starts without re-running reinit, while an **interrupted** reinit leaves the baseline missing and the next start repairs the tree. A project with no `.sha` yet (freshly added, or upgraded from before this feature) triggers one reinit to establish it.

Because the baseline is per project, a **global** change (including the `version` bump `devbot update` writes) makes _every_ project reinit on its own next start — there is no global baseline file.

- If reinit succeeds, the start proceeds normally.
- If reinit **fails**, dev-bot reports the error and **aborts the start** (non-zero exit) — the harness never launches on half-built wiring. Fix the cause and run `devbot reinit`. (There is no "continue anyway" override.)
- Editing `opencode.jsonc`/`.mcp.json` directly does **not** trigger this — those are outputs of init, not inputs.
- `make up` / `devbot up` alone do not trigger it — only a bare `devbot` start (harness launch). `up.sh` refreshes the baseline only when it was _already_ clean, so a standalone `devbot up` can never consume a pending change.

### Auto-update on start

A bare `devbot` start runs `devbot update` first (quietly), so the install is brought to the newest release before wiring. `update` is a clean no-op when already on the newest tag. Set the global `auto_update` to `false` to opt out.

When `update` moves to a new release it writes the tag into the global config's `version`. That changes each project's wiring hash, so every project reinits on its own next start — see [Auto-reinit on config change](#auto-reinit-on-config-change). If the update fails (offline, conflict), dev-bot warns and continues the start on the current version.

## Properties

### `version`

```jsonc
{ "version": "1.4.0" }
```

**Type:** `string`
**Required:** no
**Default:** absent (the dist config seeds `""`)
**Scope:** global

The installed dev-bot release tag. Written by `devbot update` when it moves onto a new release; not meant to be edited by hand. A change here changes each project's combined wiring hash, so every project reinits on its next start.

---

### `auto_update`

```jsonc
{ "auto_update": true }
```

**Type:** `boolean`
**Required:** no
**Default:** `true`
**Scope:** global

When not `false`, a bare `devbot` start runs `devbot update --auto` before wiring. The update is a no-op when already on the newest release; a failure warns and the start continues on the current version.

---

### `project_name`

```jsonc
{ "project_name": "my-project" }
```

**Type:** `string`
**Required:** no
**Default:** `"devbot"` (fallback)

The project name. Used by **search-memories** and **qmd** to auto-detect the QMD collection name (falls back to `"devbot"` if absent).

---

### `harness`

```jsonc
{ "harness": "opencode" }
```

**Type:** `string` (`"opencode"` \| `"claudecode"`)
**Required:** no
**Default:** `"opencode"`

Selects which harness DevBot configures. Project config takes precedence over global; invalid values fall back to `"opencode"`.

Used by `_devbot_get_harness` to select the launch script (`src/harnesses/<harness>/start.sh`).

---

### `devbot_dir`

```jsonc
{ "devbot_dir": ".agents" }
```

**Type:** `string`
**Default:** `".agents"`
**Required:** no

Base directory for all devbot project state: memory vault, logs, thinking files. Set to override the default location (e.g. `.my-custom-state`). All devbot subdirectories (`memory/`, `logs/`, etc.) live under this path relative to the project root.

Used by memory init, qmd init, the auto-recover and remember-session plugins, harness delegation, module symlinking, and gitignore setup.

---

### `commit_memory`

```jsonc
{ "commit_memory": false }
```

**Type:** `boolean`
**Default:** `false`
**Required:** no

When `true`, the memory vault is committed to version control instead of being gitignored. When `false` (default), the `memory/` directory is excluded via `.git/info/exclude`.

Project config takes precedence over global: an explicit value in `.devbot.project.jsonc` wins; otherwise the value from `.devbot.global.jsonc` is used; unset in both means `false`.

Used by memory init and the devbot init gitignore step.

---

### `worktrees`

```jsonc
{ "worktrees": true }
```

**Type:** `boolean`
**Default:** `true`
**Required:** no

When `true` (default), agents isolate each task's commits in a linked git worktree under `<devbot_dir>/worktrees/`, cut from the remote default branch, leaving the main checkout untouched. When `false`, agents edit and commit in the main checkout as before, and the worktree tool refuses to create one.

Project config takes precedence over global: an explicit value in `.devbot.project.jsonc` wins; otherwise the value from `.devbot.global.jsonc` is used; unset in both means `true`.

Used by the `worktree` tool (`enabled` / `create`) and the `git-worktrees` skill.

---

### `modules`

```jsonc
{ "modules": { "claudecode": false, "litellm": false } }
```

**Type:** `object` (map of module name → `boolean`)
**Default:** `{}` (every module enabled)
**Required:** no
**Scope:** project overrides global **per key**

Per-module enablement. A module set to `false` is skipped during lifecycle scripts (init, install, update, prereq checks) — its scripts, symlink wiring, and declared MCP servers are all skipped. A module absent from both files is enabled. The global and project maps merge per key, with the project value winning, so a project can re-enable a globally disabled module, or vice versa.

Disabling a module also removes its MCP servers from every harness config — this is the lever for dropping a heavy server's tool-schema and process cost (see [MCP configuration](/mcp-config#reducing-the-footprint)).

---

### `codebase_index_provider`

```jsonc
{ "codebase_index_provider": "codebase-index" }
```

**Type:** `string` (`"codebase-index"` \| `"codebase-memory"`)
**Default:** `"codebase-memory"`
**Required:** no
**Scope:** global only

Selects which codebase-understanding engine is active. The two engines are
interchangeable — the same slot in the agent toolkit, swapped by flipping this
one key (then running `devbot reinit`):

| Value               | Engine                                                                  | Integration           |
| ------------------- | ----------------------------------------------------------------------- | --------------------- |
| `"codebase-index"`  | `opencode-codebase-index` (Ollama `nomic-embed-text` embeddings)        | opencode plugin + MCP |
| `"codebase-memory"` | `codebase-memory-mcp` (DeusData — bundled native embeddings, no Ollama) | MCP server            |

The two modules are **mutually exclusive**: `_devbot_get_disabled_modules`
auto-appends the non-selected engine to the disabled set, so exactly one is
ever wired. An explicit `modules`-map `false` on the _selected_ engine still
hard-disables it (no codebase engine); enabling the _non-selected_ one via
`modules` is ignored.

**Upgrade note:** existing installs that do not set this key get the
`codebase-memory` default and will stop registering `codebase-index` on the
next reinit. Pin `"codebase_index_provider": "codebase-index"` _before_
updating dev-bot to keep the previous engine.

**Behaviour on disable (read before flipping):** disabling a module — via this
key or the `modules` map — **unregisters** its declared opencode plugin/MCP
entries at the next `devbot reinit`, not merely stops future registration. This
is required for the engine swap: a flipped-off engine must shed its
registrations. `devbot init`/`reinit` rewrite `opencode.jsonc`, `.mcp.json` and
the per-project config from module manifests — existing configs are **not
backed up**; the old file is replaced. Skills, agents, commands, and tool
symlinks are removed outright and regenerated from source. Review the current
config before reinit if you have hand-tuned entries for a module you are about
to disable.

---

### `codebase_memory_root`

```jsonc
{ "codebase_memory_root": "/home/user/projects" }
```

**Type:** `string` (absolute path)
**Default:** derived — the common ancestor of `$HOME` and every existing
registered project (`projects`), never narrower than `$HOME` and never `/`.
**Required:** no
**Scope:** global only

The repository root the shared `codebase-memory` gateway bind-mounts read-only
at the same absolute path. A project outside this root is invisible to the
gateway — its index silently stays empty — so set this when a project lives in
a tree disjoint from `$HOME` (the common ancestor would resolve to `/` and fall
back to `$HOME`).

Precedence: an explicit `CODEBASE_MEMORY_ROOT` environment variable wins, then
this key, then the derived ancestor. On `devbot up`, an explicit value (process
environment or the repo `.env`) is **persisted** into this key so an env-less
later invocation — the harness-launch `devbot` — resolves the same mount instead
of reverting to the derived default. Derived values are never persisted, so
adding a project outside `$HOME` still widens the root automatically. A `/` or
relative value is rejected. The persisted root applies to every project on the
machine; to clear it, delete this key and re-run `devbot up`.

---

### `memory_search_provider`

```jsonc
{ "memory_search_provider": "qmd" }
```

**Type:** `string` (`"qmd"` \| `"mdctx"`)
**Default:** `"mdctx"`
**Required:** no
**Scope:** global only

Selects which memory-search engine is active. The two engines are
interchangeable — the agent-facing entry point (`search-memories`) stays the
same and dispatches to whichever engine this key selects (both search the
project memory vault and the shared global store); the engine's own MCP server
and skill are registered for the selected engine only. Swap by flipping this
one key, then running `devbot reinit`:

| Value     | Engine                                                                                                                             | Integration                    |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `"qmd"`   | `@tobilu/qmd` (BM25 keyword search over per-project collections — no models, no embeddings)                                        | CLI (guard-blocked for agents) |
| `"mdctx"` | `mdctx` (zachkepe/mdctx — zero-ML-dependency RAKE + BM25 keyword index over a flat, git-diffable JSON file; no embeddings, no GPU) | MCP server + CLI               |

The two modules are **mutually exclusive**: `_devbot_get_disabled_modules`
auto-appends the non-selected engine to the disabled set, so exactly one is
ever wired. An explicit `modules`-map `false` on the _selected_ engine still
hard-disables it (no memory-search engine); enabling the _non-selected_ one via
`modules` is ignored. The qmd/mdctx pair is independent of the
`codebase_index_provider` pair — both auto-exclusions apply.

**Both engines are keyword-only:** `mdctx` is keyword-only by design (RAKE +
BM25, no embeddings); `qmd` is used BM25-only through the memory module — no
model download, no embeddings (ADR `20260913072905-qmd-bm25-only-no-model-
downloads`). Memory search is deterministic BM25 against descriptive
titles/keywords under either engine.

**Upgrade note:** existing installs that do not set this key get the `mdctx`
default and will stop registering `qmd` on the next reinit. Pin
`"memory_search_provider": "qmd"` _before_ updating dev-bot to keep the
semantic/GPU engine and its existing collections.

**Flip:** after changing the key, run `devbot reinit` so the newly selected
engine's MCP/skill is registered, the losing engine's entries are pruned, and
its index is built (`mdctx build` of the project vault + global store, or qmd
collection registration).

**Behaviour on disable** matches `codebase_index_provider` above: disabling a
module unregisters its declared plugin/MCP entries at the next `devbot reinit`.

---

### `devbot:guards`

```jsonc
{
  "guards": [
    { "regex": "rm -rf", "message": "rm -rf is blocked" },
    { "regex": "sudo .*", "message": "sudo is blocked" },
    { "regex": "git push --force", "message": "force push is prohibited" },
  ],
}
```

**Type:** `array` of guard objects
**Required:** no

Each guard rule has:

| Field     | Type     | Description                                                                                                                        |
| --------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `regex`   | `string` | Regex pattern matched against the shell command (case-sensitive) — the bash tool, or a PTY invocation normalised to `command args` |
| `message` | `string` | Block reason shown to the user when the rule matches                                                                               |

Used by the **guards** module (`on-tool_execute_before-guards.ts` opencode hook, `on_tool_execute_before-guards.sh` claudecode hook). Guards from the global config and the project config are concatenated; the first matching rule wins (project rules are evaluated before global rules).

---

### `auto_recover.max_attempts`

```jsonc
{
  "auto_recover": {
    "max_attempts": 5,
  },
}
```

**Type:** `number` (inside `auto_recover` object)
**Default:** `5`
**Required:** no

Maximum number of automatic recovery attempts per session after a transient provider error (API timeout, 5xx, overloaded). Prevents infinite retry loops — when the ceiling is hit, the error surfaces to the user.

Used by the **auto-recover** plugin (`on-session_error-auto-recover.ts`).

---

### `gpu_enabled`

```jsonc
{ "gpu_enabled": false }
```

**Type:** `boolean`
**Default:** `false`
**Required:** no
**Scope:** global only

Enables GPU acceleration for local inference (QMD/Ollama). Set automatically by `devbot install` / `devbot update` (devbot-level detection, not the ollama module install); never by a bare start.

A module that needs GPU passthrough ships a `docker-compose.gpu.yml` beside its compose (ollama's is `src/tools/ollama/docker-compose.gpu.yml`; codebase-index ships one that `include:`s it). It is appended only when this is `true` **and** a live container-passthrough probe (`_has_docker_gpu`) succeeds — on Docker Desktop (macOS/Windows) passthrough is unavailable, so a stray `true` cannot break `devbot up`. Because the overlay follows the compose it overrides, it can never be applied without the service it targets. qmd's own GPU selection is independent of this flag: it probes the host directly.

---

### `ollama_local_api`

```jsonc
{ "ollama_local_api": "http://localhost:18434" }
```

**Type:** `string`
**Default:** `"http://localhost:18434"`
**Required:** no
**Scope:** global only

Local Ollama API endpoint, read by the ollama model-pull helper (`_ensure_ollama_models_detached` in `src/_shared/functions.sh`) when it fetches missing models; the `OLLAMA_API_URL` environment variable overrides it for a single run. It is dormant unless the codebase-index engine is enabled.

---

### `projects`

```jsonc
{ "projects": ["/path/to/project-a", "/path/to/project-b"] }
```

**Type:** `array` of `string`
**Default:** `[]`
**Required:** no
**Scope:** global only

Absolute paths of projects registered with DevBot. Managed by the project-registration helper (`add_project.py`).

---

### `datasources`

```jsonc
// .devbot.global.jsonc — the catalogue, declared once
"datasources": {
  "hotels-dev": {
    "type": "mysql",
    "env": {
      "MYSQL_HOST": "localhost",
      "MYSQL_USER": "root",
      "MYSQL_PASSWORD": "${HOTELS_DEV_DB_PASSWORD}"
    }
  }
}
```

```jsonc
// .devbot.project.jsonc — opt in, by name
"datasources": ["hotels-dev"]
```

**Type:** `object` (global) / `array` of names (project)
**Default:** `{}` / `[]`
**Required:** no
**Scope:** the catalogue is global-only; the selection is per project

Database access for agents, through one shared MCP Toolbox gateway on
`127.0.0.1:18510`. The catalogue is declared once; each project opts in by name.
A datasource a project does not name is never registered with its harness, so it
costs nothing — not even context.

The `env` map names the engine's own variables (`MYSQL_HOST`, `MONGODB_URI`,
`MONGODB_DATABASE`, …). Each **value** is either a literal or a `${VAR}`
reference to an environment variable:

| Value                         | Meaning                                                   |
| ----------------------------- | --------------------------------------------------------- |
| `"localhost"`                 | A literal, written into the rendered config               |
| `"${HOTELS_DEV_DB_PASSWORD}"` | Resolved from the environment — the value reaches no file |

A reference must be the **whole** value: `pre-${VAR}` is a literal, so a password
containing `${` is never mistaken for one. Non-secret values read best inline,
and anything secret belongs behind a reference. The environment is the repo
`.env` (which `devbot up` loads) or your shell.

Fields left out fall back to the engine's defaults, so declare only what
differs: `MYSQL_PORT` defaults to 3306, and an omitted `MYSQL_DATABASE` leaves
the source with **no default schema** — one datasource then covers every database
on the instance, reachable by qualifying names
(`SELECT ... FROM otherdb.sometable`). MongoDB is the exception: its aggregate
tool requires a database, so one mongo datasource covers one database. A
`mongodb+srv://` URI is resolved by the toolbox itself — dev-bot never parses
the URI, so SRV records need no port assumption.

`type` is `mysql` (MariaDB included), `postgres`, `sqlite`, `mongodb` or
`redis` — or a **sidecar** type (`opensearch`, `s3`), served by its own container
instead of by the shared gateway (see [Sidecar datasources](#sidecar-datasources)).

**Redis** fits the same one-free-form-tool shape, by a different route. Its
toolbox tool runs a _fixed_ command list — but an array argument is flattened
into the command, so a single array parameter templating the whole command makes
the command **name** a runtime value too: the agent supplies
`["GET", "some-key"]`, exactly as it supplies a SQL statement elsewhere. One
endpoint per datasource (`address` is a sequence upstream, even for a single
host), and `username` / `password` are omitted unless declared — an empty AUTH
string is not the same as no AUTH.

Two behaviours are worth knowing before relying on it:

- **Only the databases reachable at startup are loaded.** dev-bot opens no
  database connections of its own: it runs the real toolbox (the only DB client)
  against the declared sources and loads only the ones it accepts — so a down
  database, a missing credential or a blocked host is excluded rather than
  taking the whole gateway down with it. The set is decided **once**, when
  `devbot up` runs: a database that comes up later is not picked up until the
  next `devbot up`. Reasons are printed on `devbot up`.
- **A connection that hangs is bounded.** mysql and postgres carry a 2s connect
  timeout, so a firewalled host fails fast instead of stalling the gateway's
  startup. MongoDB gets the same bound in its URI (`connectTimeoutMS` /
  `serverSelectionTimeoutMS`) — set one yourself in the URI, or in the variable
  behind it, to override it for a cluster that honestly needs longer. The redis
  source exposes no dial timeout at all in toolbox 1.11.0, so a blackholed redis
  host is still excluded, but only after the canary's full 5s deadline.
- **Nothing blocks writes.** A datasource is exactly as writable as the database
  user it is given — which is how one config serves a writable dev database and
  a read-only production one. Point production at a read-only user.

### Sidecar datasources

Some data sources have no toolbox source at all, so their `type` names a
**sidecar**: a small MCP server in its own container, on its own port, rather
than a toolset on the shared gateway. The declaration is unchanged — a `type`
and an `env` map — so a project opts in exactly as it does for a database.

```jsonc
"datasources": {
  "prod-search": {
    "type": "opensearch",
    "env": {
      "OPENSEARCH_URL": "https://search.example.com",
      "AWS_REGION": "eu-central-1",
      "AWS_ACCESS_KEY_ID": "${OPENSEARCH_KEY_ID}",
      "AWS_SECRET_ACCESS_KEY": "${OPENSEARCH_SECRET}"
    }
  },
  "artifacts": {
    "type": "s3",
    "env": {
      "AWS_REGION": "eu-central-1",
      "AWS_ACCESS_KEY_ID": "${ARTIFACTS_KEY_ID}",
      "AWS_SECRET_ACCESS_KEY": "${ARTIFACTS_SECRET}"
    }
  }
}
```

| Type         | Server                                                                                          |
| ------------ | ----------------------------------------------------------------------------------------------- |
| `opensearch` | the OpenSearch project's `opensearch-mcp-server-py`, streamable-http                            |
| `s3`         | dev-bot's own read-only S3 server — `list_buckets`, `list_objects`, `head_object`, `get_object` |

Ports come from the same block as the gateway (`18500–18599`, after 18510),
allocated by **sorted datasource name**, so a reinit renders the same ports
whatever order the catalogue is in.

**Credentials are environment variables**, like every other datasource: the
variable _names_ are declared and compose interpolates the values from the
environment `devbot up` builds — no credential value is written to a config or to
a rendered file. Nothing mounts `~/.aws` into a sidecar, so a sidecar that talks
to AWS takes `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`
(plus `AWS_REGION`) rather than a profile.

An unset `${VAR}` a sidecar declares is reported as a `WARN` during the render —
not refused, because a sidecar with unset credentials still starts and fails only
when first called. Engines, by contrast, are excluded outright when their env is
incomplete.

**A sidecar is not probed at startup.** The availability canary exists because
toolbox treats one unreachable source as fatal — a single down database would
take every datasource with it. A sidecar is its own container and cannot do that,
so one that fails to start fails only its own manifest, which surfaces when the
agent first calls it.

## Example: full project config

```jsonc
{
  // Project identity
  "project_name": "my-api",

  // Harness selection
  "harness": "opencode",

  // Devbot state directory
  "devbot_dir": ".agents",

  // Commit the memory vault to version control
  "commit_memory": false,

  // Isolate each task's commits in a worktree (false = commit in the main checkout)
  "worktrees": true,

  // Data sources this project may use, by name (see `datasources` above)
  "datasources": ["hotels-dev"],

  // Per-module enablement — `false` skips a module during lifecycle scripts
  "modules": { "claudecode": false, "react": false, "signoz": false, "svelte": false },

  // Guard rules for bash commands
  "guards": [
    { "regex": "rm -rf", "message": "rm -rf is blocked" },
    { "regex": "sudo .*", "message": "sudo is blocked" },
    { "regex": "git push --force", "message": "force push is prohibited" },
  ],

  // Auto-recovery
  "auto_recover": {
    "max_attempts": 5,
  },
}
```

## See also

- `.devbot.global.dist.jsonc` / `.devbot.project.dist.jsonc` — shipped config templates
- `src/tools/devbot-cli/init.sh` — Writes the default project config
- `src/agentic/guards/` — Guard rule evaluation
- `src/agentic/auto-recover/` — Auto-recovery plugin
