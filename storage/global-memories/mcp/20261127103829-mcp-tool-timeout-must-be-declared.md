---
date: 2026-11-27
keywords: ["mcp", "timeoutMs", "mcp-meta", "tool-timeout"]
aliases: ["MCP tool killed at 120s", "server default tool timeout"]
trigger-on: ["mcp-tool-authored"]
---

## A long-running MCP tool must declare timeoutMs in its mcp-meta

The `devbot-tools` server bounds every tool call at 120 s unless the tool's `mcp-meta` JSON declares
`timeoutMs` (`start-tools-mcp.ts` reads `tool.timeoutMs ?? toolTimeoutMs()`). A tool whose CLI waits
longer — `pr-watch`'s 900 s review wait, `deploy-wait`'s 1800 s deploy wait — is killed at two minutes
with the server's "timed out after 120000ms and was killed", so the caller gets a transport death
instead of the exit code the tool would have returned, and the tool's own `--timeout` is unreachable.
Declare a bound with headroom over the tool's own default (both tools now declare 3 600 000 ms), and
assert the relation in the tool's tests — the two values live in different files and drift silently.
