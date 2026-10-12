---
date: 2026-10-12
keywords: ["subagent", "task", "mcp", "general-purpose", "devbot"]
aliases: ["general-purpose agent", "task tool", "harness subagent", "generic subagent"]
---

# The general-purpose subagent is a harness built-in, not a dev-bot agent

## The fact

dev-bot ships no agent definition for a generic worker. `general` (opencode) and `general-purpose`
(claudecode) are harness built-ins. `src/harnesses/opencode/opencode.dist.jsonc` only sets models for
the named dev-bot agents (DevBot, Expert, Designer, TeamLead, Architect, PO, Critic, Developer,
Tester, Reviewer, Security, Scout), and nothing under `src/agentic/` defines a `general` /
`general-purpose` agent file. The harness exposes the generic type regardless, and the config's
`permission` block does not restrict it.

## Consequence for ported Claude Code patterns

A Claude Code pattern that says "use the `Task` tool with the `general-purpose` agent" (e.g.
hotels-portal's `/design-qa-all` fan-out, one child per page) ports to dev-bot as "the harness's task
tool -> general subagent" — only the wording differs per harness, the capability is the same. The
inline block a child returns also matches dev-bot's existing @Expert / @Designer delegation pattern,
so no on-disk deliverable is required.

## MCP tool availability is gated by the server's `enabled`, not the agent

The harness config does not restrict MCP tools per agent, so the generic subagent gets a module's MCP
servers once those servers are running. The real gate is the server's `enabled` field: a server
declared `enabled: false` (playwright, figma, chrome-devtools, ...) is not started, so the child has no
such tools until the consumer enables the module. Enabling the module — not editing agent config — is
what unlocks the tools for the child.
