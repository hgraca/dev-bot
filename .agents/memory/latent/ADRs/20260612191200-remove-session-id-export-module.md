---
date: 2026-06-12
keywords: ["devbot", "session-id", "opencode", "plugin-api", "context.sessionID"]
---

## Removed session-id-export module — session ID now accessed via native OpenCode API

Removed the entire `src/agentic/session-id-export/` module (tool, plugin, Claude Code hook, skill, tests). The module's purpose was to write the OpenCode session ID to a per-PID temp file so child processes could read it. This worked via a `tool.execute.before` plugin that read `input.sessionID` and wrote it to `$TMPDIR/opencode-session-$OPENCODE_PID` plus set `process.env.OPENCODE_SESSION_ID`.

The session ID is now accessible directly through the OpenCode plugin API without needing a dedicated module: `context.sessionID` in custom tool `execute` functions, `input.sessionID` in hook handlers (`tool.execute.*`, `chat.params`, `stop`), and `event.session_id` on session lifecycle events (`session.created`/`session.deleted`). The sole external consumer (`watermark-session.sh`) was updated to check `$OPENCODE_SESSION_ID` env var first with the legacy file path as fallback. The two skills that teach creating plugins and tools (`create-opencode-hook`, `create-opencode-tool`) were updated with dedicated Session ID Access sections documenting all three access patterns.
