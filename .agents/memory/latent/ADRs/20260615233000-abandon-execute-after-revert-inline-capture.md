---
date: 2026-06-15
keywords: ["devbot", "opencode", "remember-session", "plugin"]
see: ["project/20260615233000-execute-after-mid-response-disruption.md", "ADRs/20260615224946-remember-session-git-commit-trigger.md"]
---

## Abandon tool.execute.after trigger for remember-session; revert to inline capture

The `tool.execute.after` approach (ADR 20260615224946) was tried and abandoned. Root cause: `tool.execute.after` fires synchronously during response assembly, not at a clean boundary like `session.idle`. When the plugin used it to inject prompts via `client.session.prompt()` or delegate to subagents, the injection arrived mid-response, disrupting the orchestrator's flow and causing subagent delegation stalls after git commits. Switched back to inline capture where the `remember-session` skill is invoked directly by the orchestrator. The plugin was renamed to `on-tool_execute_after-git_commit-remember-session.ts` but is no longer used for prompt injection. Proper idle-gated execution (session.idle checking for recent commits) is the correct architecture, but requires design changes to avoid the idle-trigger non-determinism.
