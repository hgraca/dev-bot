---
date: 2026-11-04
keywords: ["opencode", "mcp", "oauth", "server-name"]
---

## opencode stores MCP auth per server name, not per URL

opencode's `mcp-auth.json` keys credentials by server name and rejects a stored entry whose URL differs, so two projects pointing one server name at different endpoints invalidate each other's token on every switch. Name per-identity servers with the identity in the name (`netsuite-<account>`, `aws-<connection>`) so they can stay authenticated side by side.
