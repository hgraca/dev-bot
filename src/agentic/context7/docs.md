---
title: "Context7"
description: "Version-accurate documentation lookup for any library or framework."
mcps:
  context7: "Version-accurate library and framework documentation"
---

Pull the documentation for the exact library version a project uses, instead of relying on what the model happened to be trained on.

## What it does

Registers the hosted Context7 MCP server (`https://mcp.context7.com/mcp`), which answers documentation queries for libraries and frameworks.

## Configuration

The server is hosted and needs no credentials; `oauth` is explicitly `false` so the client does not race the endpoint with OAuth discovery. Registered on `devbot init` when the module is enabled.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
