---
title: "Vite"
description: "Vite build tooling for an agent: vendored Vite and Vitest conventions, with a runtime MCP client."
mcps:
  vite: "Live access to a running Vite dev server"
---

Vite's build-tool and test conventions, plus an MCP client for a running Vite app.

## What it does

- **`vite`** — an MCP client pointed at the Tidewave endpoint inside a running Vite dev server (`http://localhost:5173/tidewave/mcp`). Tidewave answers from the package versions the project actually installed, so its documentation and source locations match the app rather than the latest release.
- **Vendored skills** — `antfu-vite` and `antfu-vitest` are linked into the project's skill farm when the module is enabled. Both are generated from the official Vite and Vitest documentation.

## Configuration

The module ships disabled, and so does its server: on opencode, enabling the module registers the endpoint and starts nothing, because there is no process for dev-bot to start. Claude Code has no per-server toggle, so a disabled entry is dropped from `.mcp.json` entirely and the endpoint is unavailable there until `enabled` is turned on in this module's manifest.

The endpoint only answers once the project has added Tidewave to it: `npx tidewave install` writes the plugin into `vite.config.ts`. Vite's MCP servers are plugins running _inside_ the dev server rather than standalone processes, so no manifest can launch one — which is why this module points at the dev server instead. Edit the `url` when the project does not serve on Vite's default port 5173.

## See also

- [React](/modules/agentic/react) — the Next.js sibling
- [Svelte](/modules/agentic/svelte) — the Svelte sibling
- [MCPs](/mcps) — the full server inventory
