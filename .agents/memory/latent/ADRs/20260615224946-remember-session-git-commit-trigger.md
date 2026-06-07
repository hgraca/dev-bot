---
date: 2026-06-15
keywords: ["devbot", "remember-session", "opencode", "plugin"]
see: ["project/20260615224946-remember-session-gotcha-trigger-is-execute-after.md"]
---

## Switch remember-session from session.idle to git-commit trigger

Replaced `on-session_idle-remember-session.ts` (366 lines, idle-triggered) with `on-tool_execute_after-remember-session.ts` (426 lines, commit-triggered). The new plugin hooks `tool.execute.after`, fires deterministically when a git commit completes, extracts commit context via `git log -1`, uses commit-hash-based dedup to avoid duplicate captures, and injects a delegation prompt instructing the orchestrator to delegate memory capture to a subagent via the `task` tool. This eliminates non-deterministic idle-based capture windows and ties memory to concrete code changes.
