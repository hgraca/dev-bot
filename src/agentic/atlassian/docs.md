---
title: "Atlassian"
description: "Jira Cloud from an agent, via the official Atlassian Rovo MCP server."
skills: ["atlassian", "jira-workflow", "create-jira-issue"]
commands: ["create-jira-issue"]
mcps:
  atlassian: "Jira Cloud work items — JQL search, sprints, boards, transitions"
---

Work with Jira from an agent: search issues with JQL, read and update work items, move them through transitions, and inspect sprints and boards.

## What it does

Wires the **Atlassian Rovo MCP server** into the harness and ships three skills: `devbot:atlassian` documents how to drive the server; `devbot:jira-workflow` binds a dev session's lifecycle to one ticket (resolve it at session start, open it before implementation, prefix the pull request, close it at wrap-up); `devbot:create-jira-issue` decides between epic, story, task and subtask and writes the `Problems:`/`Solutions:` description. The server is Atlassian's own hosted one (`https://mcp.atlassian.com/v2/mcp`), so the tool surface tracks Atlassian's releases rather than a dev-bot copy.

`/create-jira-issue` creates a work item outside a dev session.

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
