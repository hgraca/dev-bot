---
date: 2026-04-16
keywords: ["qmd", "xdg_cache_home"]
---

## M-ARCH-005: Environment variable injection for tool configuration

QMD has no CLI flag to configure its cache/index location; it always uses XDG_CACHE_HOME
When a tool lacks configuration flags, use environment variables. For DevBot: set XDG_CACHE_HOME in shell wrapper, MCP registration, and init scripts. Store the path in storage/secrets/ and reference it in opencode.jsonc via {file:...} syntax.
