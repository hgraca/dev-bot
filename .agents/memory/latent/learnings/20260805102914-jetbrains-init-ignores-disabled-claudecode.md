---
date: 2026-08-05
keywords: ["devbot", "jetbrains", "disabled-tools", "mcp.json", "claudecode"]
---

## jetbrains/init.sh wrote .mcp.json even when claudecode tool was disabled

The `_configure_both()` function in `src/agentic/jetbrains/init.sh` called `_write_claude()` unconditionally — it had no awareness of whether the `claudecode` tool was in `disabled_tools`. Result: running `devbot init` with claudecode disabled still created `.mcp.json` at the project root (with a jetbrains MCP entry), because jetbrains is an agentic module (checked against `disabled_modules`) and was still enabled.

Fix (commit `2e48c828`): removed `_configure_both()`, inlined OpenCode and Claude Code registrations separately in `main()`. Claude Code registration is now gated on `_devbot_get_disabled_tools` — if `claudecode` is in the list, `.mcp.json` is skipped entirely.

Pattern to watch for: any agentic module init.sh that writes to `.mcp.json` must check `disabled_tools` for `claudecode` first — `.mcp.json` is a Claude Code artifact and should not exist when claudecode is disabled.
