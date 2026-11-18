---
title: "Web search"
description: "Current information from the web, via the Exa API."
mcps:
  websearch: "Web search via Exa"
---

Reach past the model's training cutoff: search the web and get current information back as readable content.

## What it does

Registers the hosted Exa MCP server (`https://mcp.exa.ai/mcp?tools=web_search_exa`), exposing `web_search_exa`.

## Configuration

The server is hosted; `oauth` is explicitly `false` so the client does not race the endpoint with OAuth discovery. Registered on `devbot init` when the module is enabled.

## Harness support

Not every harness needs it. **OpenCode 2.x** ships a first-class websearch tool, so the module is **not
registered there at all** — this server exposes one tool, and a duplicate search surface costs its
schema and instruction block in every session for nothing. The exclusion is unconditional (the
module's enabled flag cannot bring it back) and `devbot reinit` says so in a `notice`. Harnesses
without a built-in search — Claude Code, and OpenCode 1.x — keep the module and get the server
normally.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
