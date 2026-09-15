---
date: 2026-09-15
keywords: ["mcp", "initialize", "handshake", "verification", "tools-list"]
trigger-on: ["mcp-server-verification", "mcp-gateway-readiness-probe"]
---

## An MCP initialize handshake proves the transport, not the server's configuration

A successful MCP `initialize` response only shows that something is listening and speaking the protocol. It says nothing about whether the server behind it is correctly configured, has its environment, or can do any work. A gateway that returns a valid handshake while its server operates on a bogus root is entirely possible — that combination shipped once and passed a "verified live" check.

Verify a bridged or proxied MCP server by **calling a tool**, which is the first thing that exercises the spawned server process:

```sh
# 1. initialize, capturing the session id the streamable-http transport returns
curl -s -D headers.txt -o /dev/null -X POST "$URL/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}'
sid=$(tr -d '\r' < headers.txt | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')

# 2. tools/list — served by the real server process, so a misconfigured one fails
curl -s -X POST "$URL/mcp" -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' ${sid:+-H "mcp-session-id: $sid"} \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

Two portability notes: the streamable-http transport requires the `mcp-session-id` header on every request after `initialize`, while a stateless server (native HTTP, no session) rejects nothing when the header is simply absent — so pass it conditionally. And `initialize` alone is a weak readiness probe; a readiness check should either call a tool or additionally assert the credentials/env it depends on.
