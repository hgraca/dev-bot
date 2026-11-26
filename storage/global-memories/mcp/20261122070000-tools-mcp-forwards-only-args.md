---
date: 2026-11-22
keywords: ["mcp", "tools-mcp", "args", "json-schema", "parameter"]
aliases: ["named parameters dropped", "tools/call arguments"]
---

## The devbot-tools MCP server forwards only `arguments.args`

`tools-mcp` invokes a discovered tool as `tools/call {name, arguments: {args: [...]}}`: it serializes exactly that one array onto the wrapper's command line and drops every other property. A tool whose `mcp-meta` declares named properties (`files`, `path`, `pattern`, `command`) therefore advertises parameters the server never delivers — the tool fails through MCP ("no argument given") while working perfectly from a shell, which is why it passes review. Always declare the canonical shape: `parameters.properties.args` as an array of strings with the CLI flags documented in its description, as `git-report.mcp.sh` does. `src/agentic/tools-mcp/tests/test_tool_meta_contract.py` now fails the suite when any tool declares another property.
