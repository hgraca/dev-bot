---
title: "Svelte"
description: "Svelte and SvelteKit conventions, with the Svelte MCP server."
skills: ["explicit-svelte"]
mcps:
  svelte: "Svelte framework integration"
---

Svelte and SvelteKit conventions for an agent, plus the Svelte MCP server.

## What it does

- **`explicit-svelte`** — the conventions skill: scaffolding, components, and SvelteKit project structure.
- **svelte** — the Svelte MCP server, reached through the shared MCP gateway (`http://127.0.0.1:18503/mcp`).

## Configuration

Registered on `devbot init` when the module is enabled. The server is served by the shared gateway, so it needs `devbot up` running like the other gateway-backed servers.

## See also

- [React](/modules/agentic/react) — the sibling framework module
- [MCP configuration](/mcp-config) — the shared gateways
