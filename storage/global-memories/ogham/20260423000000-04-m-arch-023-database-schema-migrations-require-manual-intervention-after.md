---
date: 2026-04-23
keywords: ["ogham", "mcp", "database"]
---

## M-ARCH-023: Database schema migrations require manual intervention after MCP upgrades

Ogham hybrid_search broke after upgrade due to Postgres function signature mismatch (10 vs 12 parameters)
MCP tool upgrades can change database schemas. Always check for and apply pending migrations after upgrading database-backed MCP servers
