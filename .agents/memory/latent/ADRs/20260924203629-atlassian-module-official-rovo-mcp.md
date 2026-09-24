---
date: 2026-09-24
keywords: ["atlassian", "mcp", "jira", "rovo"]
---

## `atlassian` module wires the official Atlassian Rovo MCP server

dev-bot gained a module (`src/agentic/atlassian/`) giving agents Jira Cloud access through Atlassian's **official** Rovo MCP Server (`https://mcp.atlassian.com/v2/mcp`, http transport, OAuth 2.1 auto-detected by opencode because the canonical manifest omits `oauth`) rather than a community Jira MCP — so tool naming, auth and permissions follow Atlassian's own semantics. It is a pure-declaration module (one canonical `mcp.json` + `skills/SKILL.md` + bats), no lifecycle scripts and no host binary. Two decisions to preserve. (1) The module ships a **first-party skill** teaching Jira workflows rather than vendoring Atlassian's official TWG CLI agent skills, because those drive the `twg` CLI binary, not MCP, and would ship broken command references; the skill deliberately does **not** hardcode MCP tool names (the official server uses camelCase, community `mcp-atlassian` uses snake_case, and both drift) — it teaches calling the server's `discover` tool first. (2) **Both gates are off by default**: `"atlassian": false` in the dist `modules` map *and* `"enabled": false` in `mcp.json` — the module is absent until opted in, and once enabled the server is registered but not started. Caveat recorded in the skill: Claude Code has no per-server on/off, so the translator drops `enabled` there and the server stays wired enabled.
