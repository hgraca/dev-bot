---
title: "Chrome DevTools"
description: "Give an agent eyes in a real browser — DOM, console, network, and performance traces."
mcps:
  chrome-devtools: "Browser inspection — DOM, console, network, performance traces"
---

Inspect a page the way the browser's own DevTools does: read the DOM, catch console errors, watch network requests, and record performance traces — with real runtime data rather than a static read of the source.

## What it does

Wires the Chrome DevTools MCP server into the harness. It is launched through the harness's `chrome-devtools-serve.mcp.sh`, and its logs land in `.agents/logs/chrome-devtools-mcp.log`.

## Configuration

`install.sh` installs the MCP server and pins its version in `versions.env`, so a session start never re-resolves `latest`; `devbot update` resolves the newest version and rewrites the pin in place.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Playwright](/modules/agentic/playwright) — the automation sibling
