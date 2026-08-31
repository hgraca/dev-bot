---
date: 2026-04-17
keywords: ["qmd", "xdg_cache_home"]
---

## Secret-file injection for MCP environment variables

When an MCP server needs an environment variable that varies per installation (e.g. `DEVBOT_ROOT`, `XDG_CACHE_HOME`), store the value in `storage/secrets/<name>` and reference it in `opencode.jsonc` via `"ENV_VAR": "{file:storage/secrets/<name>}"`. opencode resolves the file at session start. This is the same pattern used for API keys but works for any string value.
