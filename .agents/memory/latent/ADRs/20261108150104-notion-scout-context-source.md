---
date: 2026-11-08
keywords: ["notion", "scout", "gather-context", "mcp"]
see: ["ADRs/20261024100956-notion-module-official-hosted-mcp.md"]
---

## Notion is a scout context source behind the same two-switch gate as Atlassian

The `devbot:gather-context` skill searches Notion for context when the `notion` module is enabled **and** the MCP server is enabled, mirroring the Atlassian/Jira wiring. The canonical availability gate lives in `devbot:notion`; the orchestrators (DevBot session start and the TeamLead gate) ask the user to enable the MCP when the module is on but the server is off, and the scout reports matches in a `## Notion` report section. The search is read-only and discovers the connection's tools first (`notion-get-tool-access`), calling `notion-connector-search` alongside `notion-search` for connected sources and falling back to the connector or the legacy `notion-ai-search` when `notion-search` is absent. No Notion ticket lifecycle was added: unlike Jira, Notion has no ticket to resolve, open or close.
