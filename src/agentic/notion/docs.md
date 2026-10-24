---
title: "Notion"
description: "Read and write Notion pages and databases from an agent, via Notion's official hosted MCP server."
skills: ["notion"]
mcps:
  notion: "Notion workspace content — search, fetch, create and update pages and databases, comments"
---

Work with Notion from an agent: search the workspace, read pages and database rows, create and update pages or databases, and read or post comments.

## What it does

Ships one skill (`devbot:notion`) documenting how to drive the **Notion MCP server**, and wires that server into the harness. The server is Notion's own hosted one (`https://mcp.notion.com/mcp`, Streamable HTTP), so the tool surface tracks Notion's releases rather than a dev-bot copy. The skill covers both directions — the read path (`notion-search`, `notion-fetch`, `notion-query-data-sources`) and the write path (`notion-create-pages`, `notion-update-page`, `notion-create-database`, comments) — with the propose-confirm-act rule for mutations.

## Configuration

The server is declared `enabled: false` in the module's `mcp.json`; enabling the `notion` module links the skill but does not start the server. On opencode, set `mcp.notion.enabled` to `true` in the generated `opencode.jsonc` and restart. Claude Code omits a disabled server from `.mcp.json`, so set `enabled: true` in the manifest and run `devbot reinit` (or add it at user scope with `claude mcp add --scope user --transport http notion https://mcp.notion.com/mcp`). Authentication is the hosted server's OAuth flow: `opencode mcp auth notion`, or `/mcp` in Claude Code. Business and Enterprise workspaces may instead use an MCP token as a bearer header for non-interactive use.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
