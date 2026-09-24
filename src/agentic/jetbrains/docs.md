---
title: "JetBrains"
description: "Use the IDE from an agent — inspections, code analysis, debugging, and database tools."
mcps:
  jetbrains: "IDE inspections, debugging, and database tools"
---

Let an agent use the same IDE you do: run inspections, navigate code, drive the debugger, and reach the database tools.

## What it does

Wires the **JetBrains IDE MCP server** into the harness — into `opencode.jsonc` and `.mcp.json` (Claude Code) — with no prompts.

The IDE assigns the port, so the module **detects** it (`ss` plus stream-endpoint probing) instead of picking one; using a random port makes the IDE close the connection. A default port is the fallback when the IDE isn't running yet. Where the generated config needs a path, it writes a token in place of a literal path so the config stays portable across machines and projects.

## Configuration

Nothing manual: `init.sh` detects and wires the server at init. The IDE must be running for the tools to connect; `JETBRAINS_PROJECT_PATH` overrides the host-side project path when the default is not the right one.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
