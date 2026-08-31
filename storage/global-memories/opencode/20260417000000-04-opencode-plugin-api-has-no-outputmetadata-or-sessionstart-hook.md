---
date: 2026-04-17
keywords: ["opencode", "plugin", "session", "tool"]
---

## opencode plugin API has no `output.metadata` or `session.start` hook

The opencode plugin API exposes only `tool.execute.before` and `event` (for `session.idle`). There is no `output.metadata` for injecting context into the agent's awareness, and no `session.start` event for running logic at session beginning. When the architecture spec assumed these existed, it required a fallback approach during implementation. Always spike on actual API capabilities before specifying approaches that depend on undocumented features.
