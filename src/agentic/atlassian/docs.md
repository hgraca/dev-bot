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

The server is declared `enabled: false` in the module's `mcp.json` — enable the `atlassian` module to register it. Authentication is the hosted server's own OAuth flow.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
