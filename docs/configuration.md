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

Scalar settings resolve project-over-global, falling back to a built-in default when neither is set (`devbot_dir`, `harness`). Map settings (`modules`, `memory_collections`) merge per key, the project value winning; list settings (`devbot:guards`) are concatenated and evaluated first-match-wins (project rules first, then global). If a file is missing, its settings are skipped.

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

The same switch governs the external-module check: unless it is `false`, every start (`devbot up` as well as a bare `devbot`) compares each git-backed external module in `vendor/` against its remote and updates the ones that moved. See [External modules](/modules/tools/external-modules#updating-on-start).

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

This key is also the **only** switch for harness enablement: exactly one harness module is wired — its `init.sh`/`reset.sh`, `opencode.jsonc` / `.mcp.json` registration, plugin and skill wiring and harness-scoped manifests run, and every other harness is treated as disabled. A harness name in the [`modules`](#modules) map is silently ignored.

Switching harness therefore leaves the previously selected one's tree (`.opencode/` or `.claude/`) in place — its reset is skipped while it is unselected, so dev-bot never deletes a harness setup it is not managing. Select that harness again and run `devbot reinit` to clean it, or remove everything with `devbot uninstall`.

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

### `workspace`

```jsonc
{
  "workspace": {
    "type": "repo", // repo | polyrepo
    "commit_memory": false,
    "workflow": "worktrees", // worktrees | trunk
  },
}
```

**Type:** `object`
**Default:** the block in `.devbot.global.jsonc` — `type: "repo"`, `commit_memory: false`,
`workflow: "worktrees"`
**Required:** no

Holds the settings that describe how a workspace behaves. The global config carries the documented
defaults; a project config carries only the keys it overrides. Each key resolves project-first, then
global, then the default above.

| Key             | Type                   | Selects                                                                |
| --------------- | ---------------------- | ---------------------------------------------------------------------- |
| `type`          | `repo` \| `polyrepo`   | whether the project is an ordinary project or a container for siblings |
| `commit_memory` | `boolean`              | whether the memory vault is committed to version control               |
| `workflow`      | `worktrees` \| `trunk` | how a task is carried end to end                                       |

#### `workspace.type`

`polyrepo` marks the project as a **container**: a session launched here orchestrates work across
the managed projects registered in the global config's `projects` array, and its **memory scope is
resolved from the files the session touches**. Working on a file under project `A`, a search covers
`A`'s vault + the shared global store + this polyrepo's own vault; a memory about `A` is stored in
`A`, cross-project knowledge in the polyrepo, and tech-generic knowledge in the global store (see
`devbot:memory-management`).

A polyrepo lives anywhere — physical nesting of the managed projects is irrelevant; the global
`projects` registry is the source of truth. Sessions launched _inside_ a managed project are
unaffected: they keep searching their own vault + the global store, never the polyrepo's.

`repo` (the default) is an ordinary project.

Used by `search-memories` and the memory skills, the `worktree` tool (`enabled` / `create` refuse a
polyrepo root), and `project-for-path`, which reports it as `type`.

#### `workspace.commit_memory`

When `true`, the memory vault is committed to version control instead of being gitignored. When
`false`, the `memory/` directory is excluded via `.git/info/exclude`.

Used by memory init and the devbot init gitignore step.

#### `workspace.workflow`

Selects the workflow an agent follows for a task — the end-to-end way the work is carried through
the project. `worktrees` isolates each task's commits in a linked git worktree under
`<devbot_dir>/worktrees/`, cut from the remote default branch, and carries it to an open pull
request. `trunk` works directly on the default branch with no pull request, and stops for the
user's gate before pushing. The workflows themselves are defined in the Workflows section of the
`software-development` skill. An explicit user instruction overrides the setting for that run.

Used by the `worktree` tool (`enabled` / `create`), `project-for-path`, and the `git-worktrees` skill.

#### Migrating a flat config

The three keys used to sit at the root of the config, next to a boolean `monorepo` (and, before
that, a boolean `worktrees`). `devbot init` rewrites such a config into this block — in the project
config and in the global one: `monorepo: true` becomes `type: "polyrepo"`, `monorepo: false`
becomes `type: "repo"`, `worktrees` maps to `workspace.workflow`, and an explicit `commit_memory`
or `workflow` is carried across as an override. A config that never runs `init` must be rewritten by
hand, because no reader falls back to the flat keys.

Every other project-scoped module follows the same owning-project rule — resolve it with
`devbot tool project-for-path <path>`. See [Polyrepo sessions](/polyrepo-sessions) for the
per-module contract.

---

### `modules`

```jsonc
{ "modules": { "signoz": false, "litellm": false } }
```

**Type:** `object` (map of module name → `boolean`)
**Default:** `{}` (every module enabled)
**Required:** no
**Scope:** project overrides global **per key**

Per-module enablement. A module set to `false` is skipped during **init** — its symlink wiring and declared MCP servers are not installed into the project. A module absent from both files is enabled. The global and project maps merge per key, with the project value winning, so a project can re-enable a globally disabled module, or vice versa.

Harness modules are **not** toggled here. Which harness is wired comes from the root [`harness`](#harness) key alone, so `"opencode"` / `"claudecode"` entries in this map are silently ignored — setting `"opencode": false` on the selected harness does not disable it, and setting `"claudecode": true` on the unselected one does not enable it.

`devbot update` merges the dist schema into an existing global config additively: a module key the runtime does not have picks up the dist default (so a newly shipped module arrives disabled or enabled exactly as declared), while a key the runtime already sets keeps the machine's value. Set a module to `true` explicitly to keep it enabled; do not rely on deleting its key, which the merge re-adds from the dist default.

The machine-wide commands ignore this map: `install`, `update`, `uninstall` and prereq checks run **every** module's scripts, disabled ones included — their assets are machine-wide, and a module disabled in one project may be enabled in another (the same rule `down` follows). Enablement is otherwise honoured by the per-project lifecycle (`init`, `up`) and by `devbot list`, which hides disabled modules' artifacts unless `--all` is given.

Disabling a module also removes its MCP servers from the selected harness's config — this is the lever for dropping a heavy server's tool-schema and process cost (see [MCP configuration](/mcp-config#reducing-the-footprint)).

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
BM25 engine and its existing collections.

**Flip:** after changing the key, run `devbot reinit` so the newly selected
engine's MCP/skill is registered, the losing engine's entries are pruned, and
its index is built (`mdctx build` of the project vault + global store, or qmd
collection registration).

**Behaviour on disable** matches `codebase_index_provider` above: disabling a
module unregisters its declared plugin/MCP entries at the next `devbot reinit`.

---

### `memory_collections`

```json
{
  "memory_collections": {
    "project": {
      "path": "{project}/{devbot_dir}/memory/latent",
      "semantic": false
    },
    "notes": { "path": "~/notes", "semantic": true }
  }
}
```

**Type:** `object` (name → `{ path, semantic }`)
**Default:** the built-in `project` + `global` pair
**Required:** no
**Scope:** project and global, merged

Lists the document collections `search-memories` and `reindex-memories` search.
The object key is the collection name; each value carries a `path` and a
`semantic` flag (default `false`).

The two built-ins are reserved:

| Key       | Where it may be set | Default path                              |
| --------- | ------------------- | ----------------------------------------- |
| `project` | project config only | `{project}/{devbot_dir}/memory/latent`    |
| `global`  | global config only  | `${DEV_BOT_ROOT}/storage/global-memories` |

Custom keys may be set in either file. The two maps merge (global first, then
project); when both define the same custom key, the project entry **replaces**
the global one wholesale. A custom collection's identity is derived from its
normalized path: its qmd collection is `dev-bot-custom-<path-hash>` and its
mdctx index is `collections/<path-hash>.json`, where `<path-hash>` is the first
12 hex characters of SHA-256. Keys and projects that name the same path share
one registration and index; different paths never collide. The logical key is
what `--collection` selects. A custom collection cannot alias another
registered project's vault; that project's own sessions own it. If the built-in
`global` path is overridden, it gets its own mdctx index under `collections/`;
the mdctx gateway continues to serve the shipped store, so the two cannot
overwrite each other.

Placeholders: `{project}` (the project root), `{devbot_dir}` (the resolved
`devbot_dir`), `${DEV_BOT_ROOT}` (the dev-bot install root), and `~` (home).
Relative paths resolve against the project root.

`semantic` is reserved: a `true` value is accepted and stored but is inert
today — both engines are keyword-only (BM25; see `memory_search_provider`), so
a search emits a `NOTICE` and runs BM25. It will select qmd's model path when
that path is restored.

In a polyrepo project, the `project` collections follow the `--focus` read
set, while the `global` and custom collections are always searched. Custom
collections resolve from the session project's config plus the global config;
a focused child's own project-level custom collections are not pulled into the
polyrepo's search (a session started inside that child searches them).

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
    "mcp_timeout_ms": 300000,
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

A field you **declare** as a `${VAR}` reference makes that variable the source of
truth: if it is unset or empty and the field has a non-empty default (a host, a
port), the datasource is excluded rather than falling back. The default applies
only to an **omitted** field. That distinction matters for hosts —
`MYSQL_HOST` / `POSTGRES_HOST` default to `localhost` only when left out, so a
variable meant to point at a production replica but empty drops the datasource
instead of silently retargeting it at your local database. A field whose default
is deliberately empty (`MYSQL_DATABASE`) keeps the datasource with no default
schema, because an empty value there means "no schema", not "fall back".

`type` is `mysql` (MariaDB included), `postgres`, `sqlite`, `mongodb` or
`redis` — or a **sidecar** type (`opensearch`, `s3`), served by its own container
instead of by the shared gateway (see [Sidecar datasources](#sidecar-datasources)).

`mcp_timeout_ms` raises the MCP client's request timeout for that source —
connect, tool listing and tool calls — in milliseconds, default `60000`. opencode
honours it; Claude Code takes its equivalent from `MCP_TIMEOUT` and ignores the
key. A change takes effect on `devbot reinit`, like the rest of the wiring.

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

### `kubectl`

Cluster access for agents, rendered by `src/agentic/k8s/init.sh` on every init.
The global node is a **catalogue**; each project opts in by naming clusters, the
way it does for `datasources` and `aws_connections`. The script then writes that
project's own `~/.kube/devbot/<project>.yaml` and
`~/.kube/devbot/<project>.env`, plus one shared exec credential wrapper
`~/.kube/devbot/exec-credential.sh`, and regenerates them from scratch — so a
cluster dropped from the selection disappears from that project's kubeconfig on
the next init.

The project slug is `project_name` (or the directory name when the config has
none), folded to `[A-Za-z0-9._-]`, plus the first eight hex characters of the
absolute path's SHA-256. The hash is what makes it unique: two checkouts both
named `demo` get different files, so initialising one can neither widen nor
overwrite another. Moving a project changes its slug and leaves the old file
behind.

```jsonc
// .devbot.global.jsonc — the catalogue every project may select from
"kubectl": {
  "profile": "devbot-agent", // AWS profile the exec plugin runs `aws eks get-token` under
  "credential_env": {
    // Destination name → ${VAR} reference, exactly as in a datasource.
    "AWS_ACCESS_KEY_ID": "${AWS_KEY}",
    "AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"
  },
  "clusters": [
    { "name": "k8s-prod", "context": "k8s-prod-ro", "region": "eu-central-1" },
    { "name": "k8s-stg", "context": "k8s-stg-rw", "region": "eu-central-1" }
  ]
}

// .devbot.project.jsonc — opt in by cluster name; nothing is rendered without it
"kubectl": ["k8s-prod", "k8s-stg"]
```

The selection's order no longer decides the default: `current-context` is the
cluster the **project's own name** names, so a project declared as
`acme-k8s-stg` opens on `k8s-stg` even when its array lists `k8s-prod` first.
A catalogue name matches when the project name equals it or ends with
`-<name>`, and the longest match wins — a catalogue holding both `k8s` and
`k8s-stg` resolves `acme-k8s-stg` to `k8s-stg`. A project whose name names none
of its clusters opens on the first selected cluster that rendered, which is why
the order still fixes the order of the entries in the file. A name the
catalogue does not declare, or a cluster that cannot be described, is reported
as a `WARN` and left out — the next selected cluster takes its place, so
`current-context` is not necessarily the first name listed. A matching cluster
the project did not select, or one that failed to describe, is not a candidate;
the first case is warned about, because the fallback may then name an
environment the project did not. A selection that matches no catalogue entry at
all prunes the project's files.

`context` is the kubeconfig context name and defaults to the cluster name.
`namespace` is not configurable: contexts open in `default`, which is where the
workloads live in this workspace. Both cluster and context names must match
`[A-Za-z0-9._-]+` — the context is emitted as a YAML plain scalar, so a value
like `"team: prod"` would be parsed as a mapping and corrupt the file.

The config lives in its own file, not in `~/.kube/config`. kubectl only reads
`~/.kube/config` unless `KUBECONFIG` says otherwise, so init also writes the
project's env file:

```sh
. ~/.kube/devbot/<project>.env   # export KUBECONFIG=~/.kube/devbot/<project>.yaml
kubectl --context k8s-prod-ro get pods
```

Keeping it separate is deliberate. Merging agent contexts into a human's admin
kubeconfig is how a `--context` typo reaches production, and the agent's
permissions only hold while the context it uses is the one carrying the exec
plugin.

**The `${VAR}` references are not resolved at init.** They are copied verbatim
into the generated exec wrapper, which the shell expands when kubectl asks for a
token — so the value only ever exists in the environment of that one process and
never in a file. This differs from a datasource, where the reference is
interpolated into a process environment at render time; here the consumer is a
file, so resolving it early would write the secret to disk. Reading
`~/.kube/devbot/exec-credential.sh` shows `${AWS_KEY}`, not a key.

`profile` must already exist in `~/.aws/config`; dev-bot does not create it,
because rewriting a shared credentials file is not an init step. A profile that
is missing, or a reference whose variable is unset, is reported as a `WARN` and
skips the render rather than writing a kubeconfig that authenticates as nobody.

A `credential_env` value **must** be a whole `${VAR}` reference. A literal is
refused: it would be copied into the wrapper, where shell metacharacters become
executable syntax and the value itself becomes a credential on disk.

Pruning is explicit and scoped to the project. Removing a cluster from its
selection drops it from the regenerated kubeconfig; emptying the selection
(`"kubectl": []`) deletes that project's kubeconfig and env file. Omitting the
project key altogether means "not configured" for that project and leaves
whatever is on disk untouched, so a template that ships no key never takes away
a kubeconfig an agent was already using. The shared wrapper is never pruned by
one project's removal: it is addressed by region and cluster name on every call
and carries only references.

Anything wider than the selection is revoked before the environment is touched:
if the existing kubeconfig lists a cluster outside the permitted set — the
selection intersected with the catalogue — it is deleted first, so a missing AWS
CLI, an expired credential or a non-role profile cannot preserve access the
project has since dropped. A selection that names no catalogue entry at all is
pruned regardless of whether AWS is reachable. A render that fails part-way keeps
the file only when every cluster in it is still permitted.

The pre-selection machine-wide `~/.kube/devbot.yaml` and `~/.kube/devbot.env` are
removed by the first init after upgrading — but only when the kubeconfig
references devbot's own wrapper, so a human's kubeconfig is never touched.

The wrapper is a `credential_source = Environment` profile plus a
`role_arn` — the profile assumes the cluster-access role, and the mapped
environment supplies the source credentials. Point `profile` at a role profile,
not at one carrying long-lived keys used directly:

```ini
# ~/.aws/config — must exist before init; dev-bot does not create it
[profile devbot-agent]
role_arn = arn:aws:iam::<account-id>:role/<cluster-access-role>
credential_source = Environment
```

That distinction is enforced rather than documented only: init resolves the
profile's identity with `sts get-caller-identity` and refuses to render when it
is not an `assumed-role` session. Environment credentials win over a profile's
own access keys, so a misconfigured profile would otherwise have the agent
acting as the source identity with whatever that key can do — a silent
escalation, visible only later in CloudTrail.

### `netsuite`

NetSuite account for the MCP server. The `netsuite` module ships **enabled by
default**; its `init.sh` builds the account URL from this value and emits a
`netsuite-<account_id>` dynamic manifest with the server `enabled: false` —
wired but not started, so it is connected from the harness when needed. The
account is part of the server name because opencode stores MCP authentication
per server name, so a production account and a sandbox can both stay
authenticated.

```jsonc
// .devbot.global.jsonc — machine default
"netsuite": { "account_id": "1234567" }

// .devbot.project.jsonc — overrides the global value for this project
"netsuite": { "account_id": "1234567-sb1", "enabled": true }
```

`account_id` is the value under NetSuite **Setup → Company → Company
Information** (`1234567`), or a sandbox ID such as `1234567_SB1`; the emitted
hostname lowercases it and turns underscores into hyphens. It must match
`[A-Za-z0-9][A-Za-z0-9_-]*`; an unset or invalid value removes the server from
the project rather than registering a broken URL. The value is not a secret —
authentication is OAuth 2.0, run once per machine by the harness (`opencode mcp
auth netsuite-<account_id>`, or `/mcp` in Claude Code). See the [NetSuite module
page](/modules/agentic/netsuite) for the NetSuite-side setup and the
different-user/role authorisation.

`enabled` (default `false`) sets the emitted server's initial state. opencode can
also flip it from its MCP dialog; set it here when the harness is Claude Code,
where a disabled server is omitted from `.mcp.json` and there is no per-server
toggle.

A project that sets `modules.netsuite: false` gets no server, and a reinit prunes
a key a previous run registered.

## Example: full project config

```jsonc
{
  // Project identity
  "project_name": "my-api",

  // Harness selection
  "harness": "opencode",

  // Devbot state directory
  "devbot_dir": ".agents",

  // Workspace behaviour — override the global defaults only when needed
  "workspace": {
    "type": "repo", // repo | polyrepo
    "commit_memory": false,
    "workflow": "worktrees", // worktrees | trunk
  },

  // Document collections searched by `search-memories`
  "memory_collections": {
    "project": {
      "path": "{project}/{devbot_dir}/memory/latent",
      "semantic": false,
    },
  },

  // Data sources this project may use, by name (see `datasources` above)
  "datasources": ["hotels-dev"],

  // NetSuite account the MCP server connects to (module enabled by default)
  "netsuite": { "account_id": "1234567" },

  // Per-module enablement — `false` skips a module during init/up
  "modules": { "react": false, "signoz": false, "svelte": false },

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
