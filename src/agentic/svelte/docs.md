---
title: "Svelte"
description: "Svelte framework integration, with vendored Svelte 5 and SvelteKit conventions."
mcps:
  svelte: "Svelte framework integration"
---

The Svelte MCP server, plus the Svelte 5 and SvelteKit conventions this module wires from vendored
skills.

## What it does

- **`svelte`** — the Svelte MCP server, reached through the shared MCP gateway (`http://127.0.0.1:18503/mcp`).
- **Vendored skills** — `mindrally-svelte`, `sveltekit-structure`, and `svelte5-best-practices` are linked into the project's skill farm when the module is enabled.

## Configuration

Registered on `devbot init` when the module is enabled. The server is served by the shared gateway, so it needs `devbot up` running like the other gateway-backed servers.

## See also

- [React](/modules/agentic/react) — the sibling framework module
- [MCP configuration](/mcp-config) — the shared gateways
