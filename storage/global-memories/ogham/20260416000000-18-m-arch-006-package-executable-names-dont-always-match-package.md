---
date: 2026-04-16
keywords: ["ogham", "mcp"]
---

## M-ARCH-006: Package executable names don't always match package names

ogham-mcp package provides 'ogham' and 'ogham-serve' executables, not 'ogham-mcp'
Verify actual executable names provided by packages rather than assuming they match the package name, especially for MCP servers
