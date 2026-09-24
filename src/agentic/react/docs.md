---
title: "React"
description: "React 18+ and Next.js conventions, with Next.js runtime diagnostics."
skills: ["explicit-react"]
mcps:
  next-devtools: "Next.js runtime diagnostics"
---

React and Next.js conventions for an agent, plus a window into a running Next.js dev server.

## What it does

- **`explicit-react`** — the conventions skill: scaffolding, components, and Next.js project structure.
- **next-devtools** — the Next.js devtools MCP server (`npx -y next-devtools-mcp@latest`), which reports runtime diagnostics from the dev server.

## Configuration

Registered on `devbot init` when the module is enabled. The devtools server only has something to say while a Next.js dev server is running.

## See also

- [Svelte](/modules/agentic/svelte) — the sibling framework module
- [MCPs](/mcps) — the full server inventory
