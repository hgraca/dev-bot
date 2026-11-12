---
date: 2026-11-12
keywords: ["devbot-tools", "session-usage", "mcp", "hooks", "context-window"]
aliases: ["caller binding", "session id injection", "context percentage"]
---

# A shared MCP server cannot name the session that called a tool

## The problem

`devbot-tools` is one long-lived stdio server per harness process. In opencode a single process can host several concurrent sessions (six were live in one project while this was built), so a tool cannot infer its caller from the working directory or from the newest session row — both picked a sibling session and reported its numbers. The server environment carries `OPENCODE_PID` but no `DEV_BOT_SESSION_ID`; only the bash tool gets that variable.

## The binding

- **opencode** — `tool.execute.before` receives `input.sessionID`. `injectSessionId` in `src/harnesses/opencode/on-hooks-utils.ts` strips any caller-supplied `--session` / `--session=` and appends the real id to `output.args.args`. The hook is the identity boundary: an explicit id is replaced, not trusted.
- **claudecode** — one process per session. A `PreToolUse` entry matching `mcp__devbot-tools__session-usage` runs the `session-arg` phase, which returns `hookSpecificOutput.updatedInput` with the same replacement.
- **fallback** — a per-harness marker file at `<devbot_dir>/logs/session-<harness>`, used only when the hook is disabled. `devbot_dir` must be a plain relative path, or the marker escapes the project.

## Reading the numbers

opencode: the `session` table's `tokens_*` are cumulative and say nothing about occupancy. Live context is `tokens.total` of the latest `step-finish` part (break same-instant ties with `rowid DESC`), and the model metadata may key the id as `modelID` or `id`. claudecode: the last assistant line's `message.usage` — input + cache_read + cache_creation + output. The context limit comes only from `~/.cache/opencode/models.json` (honouring `XDG_CACHE_HOME`); a model absent there reports "limit unknown" rather than a guessed number.
