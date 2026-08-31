---
date: 2026-04-24
keywords: ["mcp", "server", "protocol", "json-rpc"]
---

## M-FLOW-068: Direct MCP client via Node.js JSON-RPC avoids opencode run overhead

The codebase-index build was originally triggered via `opencode run`, which spins up an entire AI agent session just to call one MCP tool. This added latency and unpredictable AI-generated output.
For deterministic MCP tool calls during installation scripts, use a direct Node.js JSON-RPC client: spawn the MCP server, send initialize → notifications/initialized → tools/call. This gives full control over the protocol, avoids AI overhead, and enables structured progress display. Use `&& EXIT=0 || EXIT=$?` for `set -euo pipefail` safety.
