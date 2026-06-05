---
date: 2026-05-03
keywords: ["mcp", "server"]
---

## MCP git server (mcp-server-git) times out when post-commit hooks run background processes

Python's subprocess waits for inherited stdout/stderr FDs to close. Backgrounded processes (`&`) inherit those FDs, so the MCP tool hangs until they finish — even though the commit itself succeeds instantly.
Fix: Redirect and disown in hooks: `bash "script.sh" >/dev/null 2>&1 & disown`
