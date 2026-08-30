# Harness Adapter Modules (Annex)

A **harness** is an agent runtime DevBot plugs into (OpenCode, Claude Code, …). Each harness lives in `src/harnesses/<name>/` and is self-contained: it owns its hooks, wiring, and config templates. Business logic stays in the agentic modules' `tools/`; the harness only adapts events → commands.

## Harness module anatomy

```
src/harnesses/<name>/
  hooks/                  Harness-specific hook code
    on-hooks.<ext>        Generic adapter — reads every hooks.json manifest
    …                     Hand-written hooks (side effects the manifest can't express)
  hooks.json              Registration for the generic adapter (claudecode-style harnesses)
  init.sh                 Wiring — links/registers hooks + writes config
  functions.sh            Thin wrapper sourcing src/_shared/functions.sh
  reset.sh                Reset per-project state
  <name>.dist.json*       Config template(s)
```

## The adapter contract

The generic adapter reads every `src/agentic/*/hooks.json` manifest and maps the six semantic events to the harness's hook API:

| Event             | Meaning                         | OpenCode mapping                     |
| ----------------- | ------------------------------- | ------------------------------------ |
| `file.edited`     | a file was saved                | `event` (type `file.edited`)         |
| `command.before`  | a shell command is about to run | `tool.execute.before` (blocking)     |
| `command.after`   | a shell command finished        | `tool.execute.after` (success-gated) |
| `session.idle`    | the session went quiet          | `event` (type `session.idle`)        |
| `session.created` | a session started               | `event` (type `session.created`)     |
| `session.error`   | a transient provider error      | `event` (type `session.error`)       |

The manifest `run` command is resolved with placeholders `{module}`, `{file}`, `{command}`, `{agent}`, `{hash}`, `{session-id}`, `{error}`, `{worktree}`, `{global-config}`, `{project-config}`. `match` filters by `file` (path regex), `content` (first-4KB regex), `tool` (tool-name list), or `command` (command regex). `blocking: true` (on `command.before`) blocks the tool when the command prints `{"blocked": true, "message": "…"}`.

## Reference implementations

- **OpenCode** — `src/harnesses/opencode/hooks/on-hooks.ts`: one plugin; a single `event` handler plus `tool.execute.before`/`tool.execute.after` cover all six events.
- **Claude Code** — `src/harnesses/claudecode/hooks/on-hooks.py`: a five-phase dispatcher (`pre-tool` / `post-file` / `post-bash` / `stop` / `startup`) because Claude Code's hook events (PreToolUse/PostToolUse/Stop/SessionStart) are separate registrations with no unified event stream.

## Adding a new harness

1. Create `src/harnesses/<name>/` with `functions.sh` (sources `src/_shared/functions.sh`).
2. Write the generic adapter `hooks/on-hooks.<ext>` that reads `src/agentic/*/hooks.json` and maps the six events to your harness's hook API: extract the payload fields → substitute placeholders → run `run`.
3. For `command.before` with `blocking`, honor the blocking contract — deny/throw when the command prints `blocked: true`.
4. Write `init.sh` to wire the adapter (symlink/register it) and emit the harness config template.
5. Register the harness in the discovery loop (`bin/init.sh` iterates `src/harnesses/*/`).
6. Add any hand-written hooks for side effects the manifest can't express (e.g. prompt injection) and document them as exceptions.

## MUST

- Business logic lives in the agentic module's `tools/`; the adapter only extracts payload + runs commands — never re-implements logic.
- Honor the six-event contract and the placeholder/blocking semantics.
- Keep the harness module self-contained — no cross-references into `src/agentic/*/hooks/`.

## MUST NOT

- Write per-module hook files under `src/agentic/*/hooks/` — that is the pre-manifest pattern.
- Hardcode module-specific logic in the adapter — it must be generic over manifests.
