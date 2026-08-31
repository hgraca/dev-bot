---
date: 2026-04-20
keywords: ["mcp", "server", "protocol"]
---

## M-FLOW-052: MCP server testing requires proper protocol sequence

Testing git MCP server connectivity
MCP protocol requires client to wait for initialize response before sending tool calls. Echo piping both requests simultaneously causes 'request before initialization complete' errors. Use proper async client or manual step-by-step testing.
