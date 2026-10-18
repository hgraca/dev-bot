---
title: "React"
description: "Next.js runtime diagnostics for an agent, with vendored React and Next.js conventions."
mcps:
  next-devtools: "Next.js runtime diagnostics"
---

A window into a running Next.js dev server, plus the React and Next.js conventions this module wires
from vendored skills.

## What it does

- **`next-devtools`** — the Next.js devtools MCP server (`npx -y next-devtools-mcp@latest`), which reports runtime diagnostics from the dev server.
- **Vendored skills** — `mindrally-react`, `mindrally-nextjs` (upstream `nextjs-react-typescript`), and `mindrally-react-best-practices` (upstream `modern-web-development`) are linked into the project's skill farm when the module is enabled.

## Configuration

Registered on `devbot init` when the module is enabled. The devtools server only has something to say while a Next.js dev server is running.

## See also

- [Svelte](/modules/agentic/svelte) — the sibling framework module
- [MCPs](/mcps) — the full server inventory
