---
date: 2026-08-23
keywords: ["devbot", "mcp", "tools-mcp", "mcp.sh"]
trigger-on: ["devbot-tools-mcp", "mcp.sh", "tools-dir-script"]
---

## MCP tools are marked with the .mcp.sh extension

Only `*.mcp.sh` scripts in a module's `tools/` directory are devbot-tools MCP tools. `_link_tools` (devbot init, `src/tools/devbot/functions.sh`) symlinks only `*.mcp.sh` into `.agents/tools/`, and `discoverTools` (`src/agentic/tools-mcp/server/start-tools-mcp.ts`) scans only `*.mcp.sh`. Helper scripts keep their plain extensions — `.sh` CLIs/workers (graphify, module.sh), `.ts` hook targets (guards, auto-recover), `.py` implementations — and are neither linked nor scanned, so they never run their full logic when the MCP server discovers tools. The `mcp-meta` subcommand still returns the tool's `name`/`description`; the `.mcp.sh` suffix is on the filename only, not the tool name. To add a tool: create `*.mcp.sh`, handle `mcp-meta` (print JSON metadata, exit 0). This replaced an earlier `mcp-meta` exit-1 guard approach.
