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

### `devbot:guards`

```jsonc
{
    "guards": [
        { "regex": "rm -rf", "message": "rm -rf is blocked" },
        { "regex": "sudo .*", "message": "sudo requires approval" },
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
        { "regex": "sudo .*", "message": "sudo requires approval" },
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
