---
date: 2026-10-06
keywords: ["impact-diagram", "cli", "mcp"]
see: ["ADRs/20261006140445-impact-diagram-doc-scope-use-case-map-scanner.md"]
---

## The impact-diagram tool is a plain bash CLI, not an MCP tool

Stakeholder rule: the impact-diagram tool must be "just a bash script, not in the MCP". It therefore
ships as `src/agentic/docs/tools/ImpactDiagram/impact-diagram.sh` — a thin bash wrapper delegating to
`create-impact-diagram.py` — with **no `mcp-meta` subcommand** and no `mcp.json` entry, so it is not
exposed in the devbot-tools palette. It follows the use-case-map layout (a tool dir under
`docs/tools/` plus a `docs/skills/impact-diagram/SKILL.md`) but stays a plain CLI the agent or a human
invokes directly.
