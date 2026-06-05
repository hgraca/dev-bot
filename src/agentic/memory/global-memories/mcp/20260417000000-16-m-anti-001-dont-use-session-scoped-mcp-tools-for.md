---
date: 2026-04-17
keywords: ["mcp"]
---

## M-ANTI-001: Don't use session-scoped MCP tools for persistent system configuration

Initial plan to use opencode-scheduler MCP tool for scheduled jobs
MCP tools are session-scoped and not available to bash scripts - use platform-native mechanisms (systemd, launchd) for system-level scheduling
