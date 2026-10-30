---
date: 2026-10-30
keywords: ["devbot", "mcp", "enabled", "env", "presence-gate"]
trigger-on: ["mcp-env-presence-gate"]
---

# MCP Env Gate Must Use Effective Enablement, Not the Canonical Default

`enabled: false` in a canonical `mcp.json` is only the default: opencode users enable the server by flipping `mcp.<name>.enabled` in `opencode.jsonc`. Making `mcp_env_refs.py --skip-disabled` skip canonical-disabled servers therefore hid a missing token for a runtime-enabled server — the failure was deferred to MCP startup. The gate scans canonical refs regardless of the declared default; the extra "token unset" notice for a server that is still off is the accepted trade-off. If skipping is ever revisited, resolve the effective state from the harness config (`opencode.jsonc` entry, `.mcp.json` presence) first, not from the manifest default.
