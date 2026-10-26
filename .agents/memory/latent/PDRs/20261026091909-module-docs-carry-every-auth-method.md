---
date: 2026-10-26
keywords: ["documentation", "module-docs", "mcp", "auth", "opencode"]
---

## Module docs pages document every auth method and its exact command

A module's `docs.md` page and its `SKILL.md` are separate surfaces: the page is user-facing (published at `/modules/<area>/<name>`), the skill is agent-facing. A module that supports more than one authentication method MUST document both on its page — the recommended path and the alternative — with the exact harness commands. Concretely, the hosted MCP modules document OAuth (`opencode mcp auth <server>`, `/mcp` in Claude Code) and the non-interactive token path (`"oauth": false` plus a `{env:VAR}` header, and which environment variable holds the token), plus any admin gate (Atlassian's Rovo MCP Permissions tab, Notion's member-only and workspace-owned-connection rules). The generic `opencode mcp auth`/`logout` commands and the Claude `/mcp` equivalent also live in `docs/mcp-config.md` under "Authenticating a server". Rationale: a reader of the module page cannot see the skill, so an OAuth-only page hid the Atlassian token path and Notion's one-sentence mention was not executable; the page alone must let a reader choose and run either method.
