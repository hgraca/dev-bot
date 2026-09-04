---
layout: page
title: Harnesses
description: How DevBot's harness adapters map declarative hooks to each agent runtime.
nav_section: docs
---

# Harnesses

A **harness** is an agent runtime DevBot plugs into — currently OpenCode and Claude Code. Each lives in `src/harnesses/<name>/` and is self-contained: it owns its hooks, wiring, and config templates. Business logic stays in the agentic modules' `tools/`; the harness only adapts events → commands.

## The adapter contract

Each harness ships one **generic adapter** that reads every `src/agentic/*/hooks.json` manifest and maps the six semantic events to the harness's hook API:

| Event             | Meaning                         | OpenCode mapping                     |
| ----------------- | ------------------------------- | ------------------------------------ |
| `file.edited`     | a file was saved                | `event` (type `file.edited`)         |
| `command.before`  | a shell command is about to run | `tool.execute.before` (blocking)     |
| `command.after`   | a shell command finished        | `tool.execute.after` (success-gated) |
| `session.idle`    | the session went quiet          | `event` (type `session.idle`)        |
| `session.created` | a session started               | `event` (type `session.created`)     |
| `session.error`   | a transient provider error      | `event` (type `session.error`)       |

The manifest `run` command resolves placeholders `{module}`, `{file}`, `{command}`, `{agent}`, `{hash}`, `{session-id}`, `{error}`, `{worktree}`, `{global-config}`, `{project-config}`. `match` filters by `file` (path regex), `content` (first-4KB regex), `tool`, or `command`. `blocking: true` blocks when the command prints `{"blocked": true, "message": "…"}`. `skipOnCreate: true` (honored by the opencode adapter only) skips dispatch when the `file.edited` is a file _create_ — rewriting hooks such as the formatters opt out of creates so a freshly-written file is never normalized before the agent's next edit (audit-48 FAIL-1); read-only hooks leave it unset so they still fire on creates. See [Hooks](/hooks) for the manifest schema.

## The adapters

- **OpenCode** — `src/harnesses/opencode/hooks/on-hooks.ts`: one plugin; a single `event` handler plus `tool.execute.before`/`tool.execute.after` cover all six events.
- **Claude Code** — `src/harnesses/claudecode/hooks/on-hooks.py`: a five-phase dispatcher (`pre-tool` / `post-file` / `post-bash` / `stop` / `startup`), because Claude Code's hook events are separate registrations with no unified event stream.

## Exceptions

`devbot:auto-recover` stays hand-written (in both harnesses) because its side effects don't fit the "run a command" model: OpenCode injects the recovery prompt via `client.session.prompt`, and Claude Code uses a two-phase PostToolUse → Stop trigger flow.

## Adding a new harness

See the `devbot:create-devbot-module` skill's annex (`references/harness-adapter.md`) for the step-by-step: create `src/harnesses/<name>/` with `functions.sh`, write the generic adapter that maps the six events, honor the blocking contract, write `init.sh` to wire it, and register it in `bin/init.sh`'s discovery loop.

## See also

- [Hooks](/hooks) — the manifest schema and semantic events
- [Module Reference](/module-reference) — agentic module anatomy
