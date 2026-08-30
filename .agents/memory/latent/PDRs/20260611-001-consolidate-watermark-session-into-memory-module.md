---
date: 2026-06-11
keywords: ["watermark-session", "memory", "module-consolidation", "refactoring"]
---

## Consolidate watermark-session module into memory module

The standalone `src/agentic/watermark-session/` module served no purpose beyond
supporting the `remember-session` workflow in `src/agentic/memory/`. Moved its
entire functionality (bash CLI tool, OpenCode custom tool wrapper, Claude Code
MCP server, skill, tests) into `src/agentic/memory/tools/watermark-session/`
and `src/agentic/memory/skills/watermark-session/`, then removed the old module.
This reduces the number of agentic modules and keeps related code colocated.
