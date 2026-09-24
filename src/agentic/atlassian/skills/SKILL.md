---
name: devbot:atlassian
description: "Use when working with Jira Cloud through the Atlassian MCP server — search issues with JQL, read/create/update/transition work items, inspect sprints and boards. Triggers on 'jira', 'issue', 'ticket', a PROJ-123 key, 'sprint', 'backlog'."
---

# Atlassian — Jira via the Rovo MCP server

The `atlassian` module wires Atlassian's **official Rovo MCP Server**
(`https://mcp.atlassian.com/v2/mcp`) — a cloud-hosted, OAuth-secured endpoint
that exposes tools across Jira, Confluence, Jira Service Management, Bitbucket
and Loom. This skill covers **Jira** work items; the same connection also backs
Confluence and the rest.

The module is opt-in and its server ships **disabled** (`enabled: false` in the
module's `mcp.json`). Enable the module and flip `enabled` to `true` in the
generated harness config before relying on the tools below.

## Authentication

The server authorizes with **OAuth 2.1**. opencode detects the server's 401 and
runs the consent flow itself, so authenticate once per machine:

```sh
opencode mcp auth atlassian
```

Tokens live with the host, never in the project config, and are **scoped to the
site (`cloudId`) the user consented to**. If a call fails with an authorization
error, re-run the command above.

**Non-interactive alternative** (CI, service accounts) — only if the organisation
admin has enabled API-token authentication. Add `"oauth": false` to this server's
manifest entry and pass the credential through `headers`, reading the token from
the environment so no secret reaches the config:

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

Use `Bearer <api_key>` for a service-account key, or
`Basic <base64(email:api_token)>` for a personal API token. A **header** value may
embed `{env:VAR}` (the translator rewrites it to `${VAR}` for Claude Code), unlike
an `env` value, which must be the whole value; `devbot init` warns when a
referenced variable is unset. Prefer OAuth 2.1 for interactive use.

## Discover tools before calling them

Tool names belong to the Atlassian server and change over time — **call the
server's `discover` tool first, then choose**. Do not assume a name from memory
or from another Atlassian MCP implementation (the official server uses camelCase
such as `searchJiraIssuesUsingJql`; community servers use different names).

The Jira family typically covers: issue search, issue read, create/edit,
transitions, comments, project and issue-type metadata, and user lookup. Treat
that as the likely shape, not a contract.

Prefer **JQL** when you need precision or a reproducible query; reach for the
**natural-language `search`** tool (Rovo semantic search) when the ask is fuzzy —
but note it can consume up to 10 Rovo credits per call.

## Read path

1. **Resolve the project key and `cloudId`.** OAuth tokens are site-scoped and
   most Jira tools take a `cloudId`. List visible projects, or ask the user.
2. **Natural language** — the Rovo `search` tool (`search("<what you're looking
for>")`). Useful for fuzzy discovery; it is Rovo semantic search and can cost
   up to 10 Rovo credits per call, so prefer JQL once the project and filters are
   known.
3. **Precise** — the JQL search tool (`jql`, `fields`, page size). Request only
   the fields you need and **paginate** rather than raising the page limit.
4. **Details** — the issue-read tool (`key`, `fields`, `expand`).

## JQL quick reference

Every query should scope to a project unless the user asked across projects.

```jql
project = PROJ AND status = "In Progress"
project = PROJ AND assignee = currentUser() AND status != Done
project = PROJ AND sprint IN openSprints()
project = PROJ AND updated >= -7d
project = PROJ AND issuetype = Bug AND priority = High
project = PROJ AND issuetype = Epic AND status != Done
project = PROJ AND assignee IS EMPTY AND status = "To Do"
project = PROJ AND (priority = Blocker OR labels = blocked)
parent = PROJ-100
```

`parent = PROJ-100` lists the children of an epic. Quote multi-word values
(`status = "In Progress"`) and use the relative-date functions (`-7d`,
`startOfWeek()`) instead of hardcoded dates.

## Write path — propose, confirm, act

Jira writes are visible to the whole team. Never mutate silently.

- **Create** — fetch the project's issue-type metadata first to learn the
  required fields and valid issue types, then create with a Markdown
  description.
- **Transition** — **list the available transitions for this issue first** to
  obtain the transition id; never guess a status move.
- **Confirm before acting** — show the user the issue, the field, and the
  old → new value, and get approval before any create, update, transition,
  delete, or comment.
- **Never bulk-edit or bulk-transition** without an explicit instruction naming
  the issues.
- **Explain the change** — after a state change, add a short comment so the
  history says why, not just what.

## Output

- Lead with the key and a link:
  `PROJ-123 — <summary> — https://<site>.atlassian.net/browse/PROJ-123`.
- Summarize in prose or a table; **do not paste raw JSON** or the whole field
  blob.
- For a search, state the JQL you ran so the result is reproducible.
- Surface blockers and errors explicitly rather than reporting an empty result
  as "no issues".
