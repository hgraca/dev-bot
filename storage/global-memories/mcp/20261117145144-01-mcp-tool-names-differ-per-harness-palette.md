---
date: 2026-11-17
keywords: ["mcp", "tool-naming", "opencode", "claudecode", "agent-instructions"]
aliases: ["palette name", "tool alias", "server.tool", "mcp__server__tool"]
trigger-on: ["agent-instruction-tool-references", "mcp-tool-name"]
---

## Never write a dotted server.tool name into agent instructions — the palette names differ per harness

Every harness renames MCP tools inside the model's palette, so a dotted `<server>.<tool>` form (which some clients and tool catalogues display, e.g. `devbot-tools.session-usage`) is callable in none of them: opencode exposes `<server>_<tool>` and Claude Code exposes `mcp__<server>__<tool>`. An agent instruction that names only the dotted form sends the agent looking for a tool that does not exist, so the instruction silently fails — and it survives review because prose has no type checker. Name the bare tool (`session-usage`) and give both harness aliases in the same sentence; `src/tools/devbot-cli/commands/audit.md` carries the same convention for auditing a palette.
