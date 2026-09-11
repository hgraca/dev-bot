---
date: 2026-09-11
keywords: ["jetbrains", "opencode", "mcp", "env-var", "portability"]
see: ["ADRs/20260908213000-mcp-manifest-consolidation.md", "learnings/20260911160319-devbot-mcp-env-gate-dynamic-manifests.md"]
---

## Jetbrains OpenCode project-path header emits an env token, not a baked path

The jetbrains module (`src/agentic/jetbrains/init.sh`) now writes the OpenCode `IJ_MCP_SERVER_PROJECT_PATH` header as a `{env:VAR}` token instead of the resolved absolute project path: `{env:PWD}` by default, or `{env:JETBRAINS_PROJECT_PATH}` when that override was set when the manifest was generated. Rationale: the generated config stays portable across machines and projects, and no host path is written to disk. The token is chosen at **init** time (from the override's presence then) but resolved by OpenCode at **launch**, so the override must also be exported in the shell that launches the harness; the launch gate now scans the dynamic manifest and flags it when missing. The Claude Code builder deliberately keeps the concrete path — not because `${VAR}` is unavailable there (it is), but because Claude leaves an unset var as an unexpanded literal, so a token would fail less loudly; extending it needs `${VAR}` spelling plus claudecode coverage. The two unused stdio builders were removed, and `{env:VAR}` semantics are now documented in `docs/mcp-config.md` and `audit.md`.
