---
date: 2026-04-16
keywords: ["obsidian", "mcp"]
---

## M-ARCH-002: External service dependencies should be launched as part of the dev environment setup

Obsidian MCP server couldn't connect because Obsidian wasn't running; integrated launch into `make up` to ensure availability
When MCP servers or other tools depend on external services (Obsidian REST API, databases, etc.), launch them as part of `make up` rather than requiring manual steps. This ensures the environment is fully functional after setup and reduces debugging friction.
