---
title: "Atlassian"
description: "Jira Cloud from an agent, via the official Atlassian Rovo MCP server."
skills: ["atlassian"]
mcps:
  atlassian: "Jira Cloud work items — JQL search, sprints, boards, transitions"
---

Work with Jira from an agent: search issues with JQL, read and update work items, move them through transitions, and inspect sprints and boards.

## What it does

Ships one skill (`devbot:atlassian`) documenting how to drive the **Atlassian Rovo MCP server**, and wires that server into the harness. The server is Atlassian's own hosted one (`https://mcp.atlassian.com/v2/mcp`), so the tool surface tracks Atlassian's releases rather than a dev-bot copy.

## Configuration

The server is declared `enabled: false` in the module's `mcp.json` — enable the `atlassian` module, then set `mcp.atlassian.enabled` to `true` in the generated `opencode.jsonc` and restart. Claude Code omits a disabled server from `.mcp.json`, so set `enabled: true` in the manifest and run `devbot reinit`.

### Authentication

OAuth 2.1 is the recommended method: nothing is stored in the repo, and every call follows the signed-in user's Atlassian permissions.

```text
opencode mcp auth atlassian     # opencode: browser consent
/mcp                            # Claude Code: run inside the session
```

For non-interactive use (CI, service accounts), an org admin must first enable API-token authentication in the Rovo MCP server settings. Then set `"oauth": false` on the server entry and pass the credential through a header, read from the environment — a service-account key as `Bearer`, or a personal API token as `Basic base64(email:token)`:

```json
{
  "mcp": {
    "atlassian": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v2/mcp",
      "oauth": false,
      "headers": { "Authorization": "Bearer {env:ATLASSIAN_API_KEY}" }
    }
  }
}
```

A header value may embed `{env:VAR}`; `devbot init` warns when the variable is unset. Access is granted by the account's Jira permissions and the org's **Rovo → Rovo MCP server → Permissions** tab; create a personal token with read/search scopes only for a read-only connection, and note that `delete_jira` and `manage_jira` are disabled by default. Prefer OAuth for interactive sessions.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
