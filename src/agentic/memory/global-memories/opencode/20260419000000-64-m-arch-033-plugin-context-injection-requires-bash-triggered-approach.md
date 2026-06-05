---
date: 2026-04-19
keywords: ["opencode", "plugin", "session", "tool"]
---

## M-ARCH-033: Plugin context injection requires bash-triggered approach

Diff-aware session context plugin design
Without session.start hooks, plugins must inject context on first tool call. Bash is reliable trigger since agents hit bash early in sessions
