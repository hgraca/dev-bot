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

Scalar settings resolve project-over-global, falling back to a built-in default when neither is set (`devbot_dir`, `harness`). List settings are merged: `disabled_modules` as a union of both files, `devbot:guards` as a concatenation evaluated first-match-wins (global rules first, then project). `search-memories` reads only the project config. If a file is missing, its settings are skipped.

### Auto-reinit on config change

Both config files are the source of truth for wiring — changing one (e.g. a `disabled_modules` flip, a provider key, `gpu_enabled`) only takes effect after a reinit. Rather than requiring a manual `devbot reinit`, the next **bare `devbot` start** detects the change and reinits the current project automatically, **before** `up.sh` runs, so the whole start sequence runs on freshly wired state.

Detection is a content hash of each config stored next to it with the extension **replaced**: `<file>.jsonc` → `<file>.sha` (e.g. `.devbot.global.jsonc` ↔ `.devbot.global.sha`, `<project>/.devbot.project.jsonc` ↔ `.devbot.project.sha` — same location, never committed). `init`/`reinit` refresh the baseline at the end of every run, so an unchanged config starts without re-running reinit. A project with no `.sha` yet (freshly added, or upgraded from before this feature) triggers one reinit to establish it.

- If reinit succeeds, the start proceeds normally.
- If reinit **fails**, dev-bot warns and asks whether to continue the start anyway; non-interactive runs (`SKIP_CONFIRM` / no TTY) warn and continue.
- Editing `opencode.jsonc`/`.mcp.json` directly does **not** trigger this — those are outputs of init, not inputs.
- `make up` / `devbot up` alone do not trigger it — only a bare `devbot` start (harness launch).

## Properties

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

### `disabled_modules`

```jsonc
{ "disabled_modules": ["claudecode", "litellm"] }
```

**Type:** `array` of `string`
**Default:** `[]`
**Required:** no

Module names to skip during lifecycle scripts (init, install, update, prereq checks). Global and project lists are merged as a union. When a module name appears, all its scripts and symlink wiring are skipped.

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

| Value     | Engine                                                                                                                             | Integration      |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `"qmd"`   | `@tobilu/qmd` (hybrid semantic + BM25 over per-project collections; llama/GPU, GGUF models)                                        | MCP server + CLI |
| `"mdctx"` | `mdctx` (zachkepe/mdctx — zero-ML-dependency RAKE + BM25 keyword index over a flat, git-diffable JSON file; no embeddings, no GPU) | MCP server + CLI |

The two modules are **mutually exclusive**: `_devbot_get_disabled_modules`
auto-appends the non-selected engine to the disabled set, so exactly one is
ever wired. An explicit `modules`-map `false` on the _selected_ engine still
hard-disables it (no memory-search engine); enabling the _non-selected_ one via
`modules` is ignored. The qmd/mdctx pair is independent of the
`codebase_index_provider` pair — both auto-exclusions apply.

**Capability difference:** `mdctx` is keyword-only by design (no semantic /
vector search, no per-document collections). Under `mdctx` the agent's memory
search is deterministic BM25 against descriptive titles/keywords; semantic
query (`qmd_query` vec/hyde) exists only when `"qmd"` is selected.

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

| Field     | Type     | Description                                                     |
| --------- | -------- | --------------------------------------------------------------- |
| `regex`   | `string` | Regex pattern matched against the bash command (case-sensitive) |
| `message` | `string` | Block reason shown to the user when the rule matches            |
| `agent`   | `string` | Optional — only apply the rule to a specific agent              |

Used by the **guards** module (`on-tool_execute_before-guards.ts` opencode hook, `on_tool_execute_before-guards.sh` claudecode hook). Guards from the global config and the project config are concatenated; the first matching rule wins (global rules are evaluated before project rules).

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

Enables GPU acceleration for local inference (QMD/Ollama). Set automatically by `ollama install`; read by opencode init to substitute the `__QMD_LLAMA_GPU__` placeholder in `opencode.jsonc`.

---

### `ollama_local_api`

```jsonc
{ "ollama_local_api": "http://localhost:18434" }
```

**Type:** `string`
**Default:** `"http://localhost:18434"`
**Required:** no
**Scope:** global only

Local Ollama API endpoint. Reserved — currently present in the shipped config but not yet read by any module.

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

    // Modules to skip during lifecycle scripts
    "disabled_modules": ["claudecode", "react", "signoz", "svelte"],

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
