---
date: 2026-06-15
keywords: ["opencode", "plugin", "tool.execute.after"]
---

# tool.execute.after fires mid-response, disrupting orchestrator flow

The `tool.execute.after` hook fires synchronously during response assembly — not at a clean boundary like `session.idle`. When a plugin uses it to inject prompts via `client.session.prompt()` or delegate to a subagent via the `task` tool, the injection arrives while the orchestrator is still assembling its response. This causes: (1) the orchestrator's response stream to be interrupted, (2) subagent delegation via task tool to stall after git commits, and (3) the injected prompt to be processed in an inconsistent session state.

`tool.execute.after` should only be used for logging, metrics, audit, or passive observation. For prompt injection or delegation that requires a clean session state, only `session.idle` guarantees the response is complete. If idle-based triggering is too non-deterministic, combine it with a gate that checks for recent commits.
