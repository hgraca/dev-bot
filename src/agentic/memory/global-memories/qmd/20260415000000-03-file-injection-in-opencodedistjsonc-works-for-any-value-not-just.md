---
date: 2026-04-15
keywords: ["qmd", "xdg_cache_home"]
---

## `{file:...}` injection in opencode.dist.jsonc works for any value, not just API keys

The `{file:.ai/devbot/secrets/<name>}` pattern in `opencode.dist.jsonc` MCP `environment` blocks reads the file content and injects it as the env var value. This works for any string — not just secrets. Used to inject the absolute DevBot storage path (`storage/secrets/qmd-cache-home`) as `XDG_CACHE_HOME` for the `qmd mcp` server. Extends the "Secret-file injection for MCP environment variables" pattern above.
