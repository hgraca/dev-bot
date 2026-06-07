---
date: 2026-06-15
keywords: ["devbot", "opencode", "plugin", "remember-session"]
---

# remember-session hook is `tool.execute.after`, not a raw git hook

The remember-session plugin at `src/agentic/memory/hooks/opencode/on-tool_execute_after-remember-session.ts` triggers on `tool.execute.after` by intercepting the Bash tool's git commit output, NOT by a post-commit git hook.

## Why it matters

- Triggering depends on OpenCode's Bash tool stdout/stderr parsing, not filesystem events
- The plugin extracts the commit hash from Bash tool output and uses it for dedup
- If a git commit is made outside OpenCode's Bash tool (e.g., external terminal, another IDE), the plugin does NOT fire — memory capture is skipped
- The delegation prompt is injected into OpenCode's prompt, not into the git commit process
