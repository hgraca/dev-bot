---
date: 2026-04-20
keywords: ["mcp", "server", "json-rpc", "stdio"]
---

## M-FLOW-051: MCP Docker containers need proper testing approach

Investigating apparently failing git MCP container
Use JSON-RPC initialize handshake to test MCP containers rather than assuming they're broken when they appear to hang. Stdio-based servers block waiting for input which can look like failure
