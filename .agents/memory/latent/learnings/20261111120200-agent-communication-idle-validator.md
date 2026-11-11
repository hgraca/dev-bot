---
date: 2026-11-11
keywords: ["agent-communication", "session.idle", "opencode", "validator"]
supersedes: ["learnings/20260928095501-session-idle-nudge-system-removed.md"]
---

# agent-communication runs a log-only validator on session.idle

`agent-communication` is still a marker/PR-URL validator, but it now has an OpenCode plugin:
`hooks/opencode/on-session-idle-validate.ts`, registered by `hooks.json` for `session.idle`. On each
idle it reads the last assistant message via `client.session.messages` and runs the existing
`tools/agent-communication.mcp.sh` validator, logging any failure to
`.agents/logs/agent-communication.log`. It is deliberately **log-only** — no prompt injection, so it
cannot loop.

Design points worth keeping:

- Run the validator with an awaited, timeout-bounded `execFile` (10 s), never `spawnSync`: the handler
  is awaited by the shared adapter, so a sync spawn blocks the plugin event loop.
- Deduplicate per session+message, but record the id only after a real validator result (exit 0/1); a
  failed invocation (exit 2, spawn error, timeout) must stay retryable.
- An in-flight guard prevents duplicate validation on overlapping idle events, but it must **queue the
  newest message** and validate it after the current run — dropping it can leave a later turn
  unchecked.
- Keep `mkdtempSync` inside the try so a temp-dir failure is logged, not thrown into the idle
  dispatch.
- The pure helpers (`lastAssistantMessage`, `textParts`, `isCheckedStatus`) are exported and covered by
  `on-session-idle-validate.test.ts` (Bun), including manifest wiring.
