---
date: 2026-04-19
keywords: ["graphify", "graph"]
---

## M-ARCH-028: MCP server dependency management with uv tools

graphify MCP server missing mcp dependency after uv tool install
When installing Python tools that act as MCP servers, explicitly include --with mcp flag and add restore step after upgrades since uv tool upgrade strips --with dependencies
