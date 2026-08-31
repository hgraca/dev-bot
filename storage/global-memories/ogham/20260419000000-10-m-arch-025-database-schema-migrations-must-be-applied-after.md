---
date: 2026-04-19
keywords: ["ogham", "mcp", "database"]
---

## M-ARCH-025: Database schema migrations must be applied after tool upgrades

ogham-mcp upgrade without corresponding database migrations
When tools like ogham are upgraded via uv, check for pending database migrations. Function signature mismatches indicate schema drift. Apply migrations from the installed schema files or run tool-specific migration commands.
