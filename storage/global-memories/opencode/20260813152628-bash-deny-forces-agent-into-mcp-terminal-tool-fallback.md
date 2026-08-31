---
date: 2026-08-13
keywords: ["opencode", "mcp", "permission", "bash", "jetbrains"]
trigger-on: ["agent-permission-config", "mcp-tool-deny", "bash-deny"]
---

## bash: deny forces a subagent to route shell commands through an MCP terminal tool

A subagent whose frontmatter has `permission: { bash: deny }` cannot use the `bash` tool, so when it needs to run a script it falls back to whatever else can execute a shell command — typically an MCP server's terminal-execution tool (e.g. `jetbrains_execute_terminal_command` / `jetbrains_execute_tool`). This happens because OpenCode permission keys wildcard-match against underlying tool names, and MCP tools are implicitly *available* to every agent unless a `"<mcpname>_*": "deny"` rule exists — `bash: deny` alone does not block MCP execution paths. Fix: remove `bash: deny` so the agent inherits the global `bash` allow (with `rm *`/`sudo *` rails), and optionally add `"<mcpname>_*": "deny"` to cut off the MCP fallback entirely. The deprecated `tools:` field uses `true`/`false`, but `permission:` uses `"allow"`/`"deny"`/`"ask"`. Seen on dev-bot's Designer agent (kimi-k3) fixed in commit `1dad0e1`; Expert had the same latent fallback.
