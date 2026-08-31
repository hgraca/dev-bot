---
date: 2026-08-25
keywords: ["opencode", "mcp", "stderr"]
trigger-on: ["opencode-mcp-stderr-tui-leak"]
---

## opencode surfaces MCP server stderr in the TUI; no config option to silence it

opencode runs local MCP servers via StdioClientTransport with `stderr: "pipe"` and displays server stderr in the TUI. Its MCP config schema has no stderr option (only `type`/`command`/`cwd`/`environment`/`enabled`/`timeout`). MCP servers that log to stderr during indexing (opencode-codebase-index-mcp watcher/reindex diagnostics, qmd CLI warnings) leak onto the TUI. Fix: wrap the server command — `bash -c "mkdir -p .agents/logs && exec <server> 2>>.agents/logs/<name>-mcp.log"` — in both `mcp.opencode.json` (command array) and `mcp.claudecode.json` (command + args). MCP protocol stays on stdout; stderr goes to a file. Applies to every local MCP server in src/agentic/*/.
