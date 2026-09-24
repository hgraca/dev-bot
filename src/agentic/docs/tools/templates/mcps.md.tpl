---
layout: page
title: "MCPs"
description: "MCP servers DevBot wires into OpenCode and Claude Code."
nav_section: docs
---

DevBot wires module-declared MCP servers plus dynamic per-project harness servers (tagged `(harness)` below) into the agent tool palette. Each module-declared server is declared once in the module's canonical `mcp.json` (harness-agnostic — see [MCP configuration](/mcp-config) for the schema and per-harness wiring) and auto-registered during `devbot init`.

<!-- GENERATED:MCPS -->

## devbot-tools MCP tools

The `devbot:tools-mcp` module's `devbot-tools` MCP server is the only MCP whose tools come from DevBot itself — it exposes the DevBot tool scripts as MCP tools, each self-describing via its `mcp-meta` subcommand:

<!-- GENERATED:MCP_TOOLS -->

All other MCP servers are external packages whose tool sets are defined by the server itself (e.g. `chrome-devtools_*`, `playwright_*`, `context7_*`).

## See also

- [MCP configuration](/mcp-config) — the manifest schema, per-harness wiring, and per-server enablement
- [Tools MCP](/modules/agentic/tools-mcp) — the module behind `devbot-tools`
