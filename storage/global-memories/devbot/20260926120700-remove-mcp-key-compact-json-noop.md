---
date: 2026-09-26
keywords: ["devbot", "mcp", "remove-mcp-key", "jsonc"]
trigger-on: ["remove-mcp-key-noop"]
---

## `remove_mcp_key.py` silently no-ops on a single-line mcp map

The tool removes an MCP server key by **text surgery**, deliberately preserving comments and layout so a reinit stays byte-idempotent. It exits 0 both when it removed the key and when it found none — the documented idempotent contract. On a compact one-line config (`{ "mcp": { "a": {…}, "b": {…} } }`) its entry parser finds nothing and the file is left untouched, so the caller reports "unregistered" while the stale key survives. Its real target is a formatted `opencode.jsonc`. When debugging a reconcile that ran but changed nothing, diff the file and reproduce with a realistic multi-line fixture rather than trusting the exit code.
