---
date: 2026-08-23
keywords: ["devbot", "list-tools", "agent-communication", "mcp.sh", "stale-reference"]
---

# devbot list tools fails on stale agent-communication.sh reference

`devbot list tools` (and `commands_tests.bats` test 6) fails with `FileNotFoundError: src/agentic/agent-communication/tools/agent-communication.sh`. The tool was renamed to `agent-communication.mcp.sh` in commit `830687e9` ("mark MCP tools with .mcp.sh extension") but the list-tools description extraction still references the old path. Pre-existing and unrelated to the failure-output-prefix work — a fix should update the stale `.sh` reference to `.mcp.sh`.
