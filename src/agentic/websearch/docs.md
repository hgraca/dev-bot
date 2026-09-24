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

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
