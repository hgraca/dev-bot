---
layout: page
title: Hooks
description: Declarative hooks shipped by DevBot modules.
nav_section: docs
---

# Hooks

Hooks fire automatically on lifecycle events — session start, provider errors, file saves, and tool execution. Each module declares its hooks in a **`hooks.json` manifest** (harness-agnostic), and each harness wires them through a **single generic adapter**:

- **OpenCode** — `src/harnesses/opencode/hooks/on-hooks.ts` reads every manifest and maps the events to the plugin API.
- **Claude Code** — `src/harnesses/claudecode/hooks/on-hooks.py` is a five-phase dispatcher (`pre-tool`, `post-file`, `post-bash`, `stop`, `startup`).

For `run` hooks the business logic lives once in each module's `tools/` entry; the adapters only extract the event payload and run the declared command. `plugin` hooks hold their logic in the hook file itself.

## Semantic events

| Event             | Meaning                         | Modules                                         |
| ----------------- | ------------------------------- | ----------------------------------------------- |
| `file.edited`     | A file was saved                | format-md, format-json, format-yml, k8s, memory |
| `command.before`  | A shell command is about to run | guards                                          |
| `command.after`   | A shell command finished        | graphify (git-commit detect)                    |
| `session.idle`    | The session went quiet          | graphify (commit check)                         |
| `session.created` | A session started               | graphify (update)                               |
| `session.error`   | A transient provider error      | auto-recover                                    |

## Manifest

A module declares its hooks in `<module>/hooks.json`:

```json
{
    "hooks": [
        {
            "id": "format-md",
            "event": "file.edited",
            "match": { "file": "\\.md$" },
            "run": ["python3", "{module}/tools/format-md.py", "{file}"]
        }
    ]
}
```

- `run` — the command, with placeholders `{module}`, `{file}`, `{command}`, `{agent}`, `{hash}`, `{session-id}`, `{error}`, `{worktree}`, `{global-config}`, `{project-config}`.
- `match` — optional filter: `file` (path regex), `content` (first-4KB regex), `tool` (tool-name list), or `command` (command regex).
- `blocking: true` — for `command.before`; blocks the tool when the command prints `{"blocked": true, "message": "…"}`.
- `log` — optional path (relative to the project root) to append the hook's output to, for hooks whose effect is otherwise invisible (e.g. a linter that only reports, unlike format hooks which mutate files).

## Two hook forms

A manifest entry either `run`s a command or delegates to a TypeScript plugin:

| Form     | Use for                                                                                 | Example                             |
| -------- | --------------------------------------------------------------------------------------- | ----------------------------------- |
| `run`    | Shell commands fired on an event                                                        | format-md on `file.edited`          |
| `plugin` | Hook logic needing the opencode `client` (prompt injection, session inspection, timers) | auto-recover, silent-stall watchdog |

`plugin` hooks are TypeScript files in `<module>/hooks/opencode/` that default-export a plugin factory. The adapter imports each one, invokes the factory with the plugin context (directory, worktree, project, and the opencode `client`), and merges the handlers it returns into its own dispatch — so they behave exactly like standalone plugins.

```json
{
    "hooks": [
        {
            "id": "auto-recover",
            "event": "session.error",
            "plugin": "{module}/hooks/opencode/on-session_error-auto-recover.ts"
        },
        {
            "id": "watchdog-silent-stall",
            "plugin": "{module}/hooks/opencode/on-watchdog-silent-stall.ts"
        }
    ]
}
```

## Registration

Manifest-declared `plugin` hooks are **not** symlinked into `.opencode/plugins/` or registered standalone by the harness init — the adapter loads them, so standalone registration would double-fire. The init skips manifest-declared hooks automatically.

## Harness differences

- **OpenCode** — the `on-hooks` adapter supports both `run` and `plugin` forms, including timer-based logic (the stall watchdog polls on an interval inside its plugin factory).
- **Claude Code** — event-driven only (PreToolUse, PostToolUse, Stop, SessionStart). Modules place shell hooks and JSON configs under `hooks/claudecode/`, which the harness links into `.claude/plugins/` and merges into `settings.local.json`. Timer-based hooks cannot run there — claudecode relies on the provider-level timeouts instead.
