---
date: 2026-08-22
keywords: ["devbot", "remember-session", "finish-flow", "agent-communication"]
---

## Remember-session triggered by finish-flow confirmation, not git commits

Decoupled memory capture from git commits. The post-commit trigger hooks (opencode `on-tool_execute_after-git_commit-remember-session.ts` and the claudecode PostToolUse/Stop hooks, plus the stale `on-session_idle-remember-session.ts` entry in `opencode.dist.jsonc`) were removed. `remember-session` now runs once, at the end, via a new finish flow in `agent-communication`: the primary agent (devbot or teamlead) must not emit `[FINISHED]` on its own initiative — it asks the user whether the work is finished (using a question tool if available), and only on "yes" runs `remember-session` then terminates with `[FINISHED]`; on "no" the user provides new directions. Rationale: the per-commit auto-capture was noisy and fired disconnected from the user's sense of completion; capturing once at the end, on explicit confirmation, aligns capture with genuine milestones and removes redundant background triggers. The finish-flow gate is encoded in `devbot.md` and `teamlead.md` under their terminal-marker gates.
