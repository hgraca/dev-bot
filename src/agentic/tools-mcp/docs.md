---
title: "Tools MCP"
description: "Expose dev-bot's own tool scripts to agents as MCP tools."
skills: ["tools-mcp"]
mcps:
  devbot-tools: "dev-bot tool scripts, exposed as MCP tools"
---

Makes dev-bot's own tools callable the way any other MCP tool is, so an agent can use them without knowing where the script lives.

## What it does

- Runs the `devbot-tools` MCP server (`tools-mcp-serve.sh`), which serves each tool script's self-description as an MCP tool.
- **`tools-mcp`** skill — how the server is structured and how a tool joins it.

## Configuration

Each tool describes itself through its `mcp-meta` subcommand, so adding a tool needs no change to the server. Registered on `devbot init` when the module is enabled; logs land in `.agents/logs/devbot-tools-mcp.log`.

## See also

- [Create an opencode tool](/create-a-module) — tool anatomy and conventions
- [MCP configuration](/mcp-config) — the manifest schema
