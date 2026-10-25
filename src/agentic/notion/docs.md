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

The server is declared `enabled: false` in the module's `mcp.json`; enabling the `notion` module links the skill but does not start the server. On opencode, set `mcp.notion.enabled` to `true` in the generated `opencode.jsonc` and restart. Claude Code omits a disabled server from `.mcp.json`, so set `enabled: true` in the manifest and run `devbot reinit` (or add it at user scope with `claude mcp add --scope user --transport http notion https://mcp.notion.com/mcp`).

### Authentication

OAuth is the recommended method: the consent flow selects the workspace and the pages/databases the connection may touch, and every call is limited by your Notion permissions.

```text
opencode mcp auth notion        # opencode: browser consent
/mcp                            # Claude Code: run inside the session
```

For non-interactive use, Business and Enterprise workspaces can issue an **MCP token** (a workspace owner creates it in the Notion developer portal). Set `"oauth": false` on the server entry and pass the token as a bearer header, read from the environment:

```json
{
  "mcp": {
    "notion": {
      "type": "http",
      "url": "https://mcp.notion.com/mcp",
      "oauth": false,
      "headers": { "Authorization": "Bearer {env:NOTION_MCP_TOKEN}" }
    }
  }
}
```

Only workspace members can connect — guests are refused — and a workspace-owned connection created by an admin exposes only the tools selected for it. Prefer OAuth for interactive sessions.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
