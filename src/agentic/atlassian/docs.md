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

`/devbot:create-jira-issue` creates a work item outside a dev session.

## Configuration

The server is declared `enabled: false` in the module's `mcp.json` — enable the `atlassian` module, then clear `disabled` on its entry in the generated `opencode.jsonc` (a v1 config writes `enabled: true` instead) and restart. Claude Code omits a disabled server from `.mcp.json`, so set `enabled: true` in the manifest and run `devbot reinit`.

### Authentication

OAuth 2.1 is the recommended method: nothing is stored in the repo, and every call follows the signed-in user's Atlassian permissions.

```text
opencode mcp auth <server-name>  # opencode: browser consent
/mcp                             # Claude Code: run inside the session
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

### A second Jira account

opencode stores OAuth credentials **per server name**, in one file shared by every project, so two projects that both call the server `atlassian` share one Atlassian login — signing in for one signs in for the other. Keep a second account by registering the same endpoint under a second name in that project's config:

```jsonc
// the project that needs the other account, in opencode.jsonc
"atlassian-wedding": {
  "type": "remote",
  "url": "https://mcp.atlassian.com/v2/mcp",
  "disabled": false        // older configs spell this "enabled": true
}
```

```text
opencode mcp auth atlassian-wedding    # signs in the second account
```

The name is a local label; the endpoint is the integration's identity. Read which name is live with `devbot tool project-for-path <project> --key atlassian_server`, which matches the module's endpoint and reports `{name, state}`, adding `candidates` whenever `name` is null — that is, when two servers are live, or when none is and several entries compete. It prefers the enabled entry, so the disabled `atlassian` stub that `devbot reinit` re-registers beside a renamed server is ignored — never sign that stub in, it would pull the project back to the other account.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
