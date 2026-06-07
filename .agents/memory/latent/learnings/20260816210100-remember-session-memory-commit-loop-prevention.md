---
date: 2026-08-16
keywords: ["devbot", "remember-session", "loop-prevention", "opencode", "git-commit"]
---

# remember-session memory-file commits are loop-safe via the post-commit tag check

When `remember-session` commits its own memory files (step 4), that commit re-fires the `on-tool_execute_after-git_commit-remember-session` hook. Automated captures cannot loop: the hook injects a synthetic user prompt whose first line is `[DevBot-RememberSession-PostCommit]`, and `hasRememberSessionTag()` checks the last user message for that tag — so any commit made during the capture is skipped on idle (clear trigger, return).

The 10-minute lock does NOT guard against this re-trigger: it is acquired and released synchronously in the same `session.idle` handler (finally block), before the agent ever does the capture work. Only the tag check prevents the loop.

Manual ("wrap up") captures have no injected tag, so a memory-file commit can queue one redundant capture; it terminates (re-scan finds nothing new, no git diff, or the duplicate check catches it) rather than looping. It only becomes eternal if the agent re-writes non-identical content each round while the QMD index stays stale — an agent bug, not a structural loop.

Reference: `src/agentic/memory/hooks/opencode/on-tool_execute_after-git_commit-remember-session.ts` (`hasRememberSessionTag` ~line 351, loop-prevention ~line 541, lock released in finally ~line 615).
