---
date: 2026-09-24
keywords: ["atlassian", "jira", "mcp", "rovo"]
trigger-on: ["atlassian-mcp-integration", "jira-mcp-server"]
---

## Atlassian's official MCP is the Rovo MCP Server — cloud-only, OAuth 2.1, one server for every product

Reach Jira from an MCP client through Atlassian's own **Rovo MCP Server**, not a community server: `https://mcp.atlassian.com/v2/mcp` (streamable HTTP; append `?tools=all` for gateways that need a complete paginated tool list). The older `/v1/sse` endpoint is deprecated after 2026-06-30. Auth is **OAuth 2.1** — interactive consent, with the token scoped to the site/`cloudId` — plus an optional org-admin-gated API token supplied as `Authorization: Basic <base64(email:api_token)>` or a service-account `Bearer <api_key>`. A single server exposes Jira, Confluence, Jira Service Management, Bitbucket and Loom; there is no per-product filter. Two traps. (1) It is **Cloud-only**: Jira Data Center/Server has no official MCP and needs the community `sooperset/mcp-atlassian` instead. (2) Atlassian also ships an official native CLI, **TWG CLI** (`twg`, installed via `https://teamwork-graph.atlassian.com/cli/install`), which bundles official agent skills into `~/.agents/skills` — those skills teach the `twg` CLI, **not** MCP, so they are not drop-in guidance for an MCP-only integration. Tool names differ between implementations (official Rovo uses camelCase such as `searchJiraIssuesUsingJql`; community `mcp-atlassian` uses snake_case such as `jira_search`) and drift over time — discover them at runtime rather than hardcoding a table. Rovo's natural-language `search` tool can consume up to 10 Rovo credits per call, so prefer JQL once the project and filters are known.
