---
date: 2026-08-23
keywords: ["devbot", "harness", "opencode", "claudecode", "slash-command"]
trigger-on: ["harness-detection", "dual-harness", "claudecode-command"]
---

## Harness-aware commands must detect the harness from the tool palette, not config

A single `harness` key in `.devbot.project.jsonc`/`.devbot.global.jsonc` does NOT tell you which harness you are running under — it only names the launch binary (`_devbot_resolve_harness_bin`). A project can have BOTH harnesses wired at once: `bin/init.sh` iterates every enabled `src/harnesses/*` module (gated by the `modules` map, `false` = disabled, absent = enabled), so `.opencode/` and `.claude/` can coexist. The authoritative "which runtime is executing me" signal is your own tool palette naming: opencode exposes MCP tools as `<server>_<tool>` (e.g. `qmd_*`, `devbot-tools_*`), claudecode as `mcp__<server>__<tool>` (e.g. `mcp__qmd__*`). Per-harness MCP config differs too: opencode reads the `mcp` block in `opencode.jsonc`, claudecode reads `mcpServers` in `.mcp.json`. Any slash command that audits MCP health must enumerate enabled harnesses (both may exist), detect the running one via tool naming, and check each harness's own config — a broken `.mcp.json` is a defect even under opencode.
