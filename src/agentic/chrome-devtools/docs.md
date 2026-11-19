---
title: "Chrome DevTools"
description: "Give an agent eyes in a real browser — DOM, console, network, and performance traces."
mcps:
  chrome-devtools: "Browser inspection — DOM, console, network, performance traces"
---

Inspect a page the way the browser's own DevTools does: read the DOM, catch console errors, watch network requests, and record performance traces — with real runtime data rather than a static read of the source.

## What it does

Wires the Chrome DevTools MCP server into the harness. It is launched through the harness's `chrome-devtools-serve.mcp.sh`, and its logs land in `.agents/logs/chrome-devtools-mcp.log`. The launcher drives the **newest** Playwright Chromium found in `~/.cache/ms-playwright` (not the first, lexicographic match): old revisions lack CDP commands the server calls — Chrome 133 has no `Browser.setContentsSize`, so `resize_page` fails there.

## Configuration

`install.sh` installs the MCP server at the pinned version — `versions.env`, seeded from the committed `versions.env.dist`; the live copy is machine-local and gitignored — so a session start never re-resolves `latest`; `devbot update` resolves the newest version, rewrites the machine's pin in place (never the shipped default), and refreshes the Playwright Chromium, so a cache that only held an old revision cannot keep `resize_page` broken.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Playwright](/modules/agentic/playwright) — the automation sibling
