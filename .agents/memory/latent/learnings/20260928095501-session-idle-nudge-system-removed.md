---
date: 2026-09-28
keywords: ["devbot", "agent-communication", "nudge", "plugin", "session-idle"]
---

# The session-idle nudge system is gone; agent-communication is a marker validator

Notes about "nudge plugins" — `agent-communication`, `remember-session` and `auto-recover` injecting hidden `{ hidden: true }` prompts on `session.idle` — describe a system that no longer exists. `agent-communication` is now a marker-validation MCP tool (`src/agentic/agent-communication/tools/agent-communication.mcp.sh`) that checks a message's last non-empty line against `\[(FINISHED|BLOCKED|NEEDS_INPUT|PARTIAL)\]`; it has no plugin and no `hooks/opencode/` directory. `src/agentic/memory/hooks/opencode/` (the remember-session plugin) is likewise gone. No module consumes the `session.idle` event anymore — the only surviving plugins are auto-recover's `on-session_error-auto-recover.ts` and `on-watchdog-silent-stall.ts`. Treat any memory referring to nudge prompts, `NEEDS_INPUT` suppression in an idle plugin, or the watermark as historical.
