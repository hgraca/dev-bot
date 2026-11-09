---
date: 2026-11-09
keywords: ["devbot", "tools-mcp", "timeoutMs", "mcp-tool", "subprocess-timeout"]
aliases: ["tool timeout 120s", "MCP kills long tool", "TOOLS_MCP_TIMEOUT_MS"]
---

## Declare `timeoutMs` in a tool's `mcp-meta` when it can outlive 120 seconds

The `tools-mcp` server kills a tool's process group after `TOOLS_MCP_TIMEOUT_MS` (default 120 s). A tool that waits on slow work — a rollout, a build, a long install — is killed mid-operation even though the work keeps running server-side, and the caller sees a timeout instead of the result. `mcp-meta` accepts an optional `timeoutMs` for exactly this; it is validated (positive safe integer, capped near 2^31) and overrides the default. Set it above the tool's worst-case runtime (an upgrade waiting on nine workloads at 300 s each needs 3,900,000 ms), and keep the script's own internal timeouts below it so the script — not the server — decides when to give up.
