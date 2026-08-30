---
date: 2026-08-25
keywords: ["devbot", "harness", "session-logs", "start.sh"]
---

## Harness start.sh rotates session logs and alerts on errors at exit

Both harness `start.sh` scripts (claudecode/opencode) run the harness as a child instead of `exec` so post-exit work is possible. Before launch they rotate `.agents/logs/*.log` to `.agents/logs/rotated/<YYYYMMDD>-<name>-<NNN>.log` (date prefix, zero-padded 3-digit sequence, old logs preserved), so writers start fresh files each session. On exit `_devbot_check_session_logs` scans the fresh logs for error-level lines (`\b(error|fatal|traceback|exception|failed)\b`, case-insensitive) and prints an alert grouped by normalized error type with per-type counts (e.g. "Watcher error: EMFILE: 2x"); full logs stay on disk. The helper always returns 0 so the harness exit code is never masked; the post-exit alert also picks up the redirected MCP server logs.
