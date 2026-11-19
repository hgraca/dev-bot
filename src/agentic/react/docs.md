---
title: "React"
description: "Next.js runtime diagnostics for an agent, with vendored React and Next.js conventions."
mcps:
  react-nextjs-devtools: "Next.js runtime diagnostics"
---

A window into a running Next.js dev server, plus the React and Next.js conventions this module wires
from vendored skills.

## What it does

- **`react-nextjs-devtools`** — the Next.js devtools MCP server (`npx -y next-devtools-mcp@latest`), which reports runtime diagnostics from the dev server. OpenCode registers it and leaves it stopped; Claude Code has no per-server toggle, so `init.sh` drops a disabled entry from `.mcp.json` and the server is unavailable there until `enabled` is turned on in this module's manifest.
- **Vendored skills** — `mindrally-react`, `mindrally-nextjs` (upstream `nextjs-react-typescript`), and `mindrally-react-best-practices` (upstream `modern-web-development`) are linked into the project's skill farm when the module is enabled.

## Configuration

Registered on `devbot init` when the module is enabled. The devtools server only has something to say while a Next.js dev server is running, so it ships disabled — turn it on per project once there is a dev server to attach to.

## See also

- [Svelte](/modules/agentic/svelte) — the sibling framework module
- [MCPs](/mcps) — the full server inventory
