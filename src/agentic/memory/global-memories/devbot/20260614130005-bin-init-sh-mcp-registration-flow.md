---
date: 2026-06-14
keywords: ["devbot", "bin/init.sh", "mcp", "registration"]
---

## bin/init.sh MCP Registration Flow

The `_register_module_mcp_servers()` function in `bin/init.sh` auto-discovers MCP servers from module files:

1. Scans `src/agentic/*/mcp.opencode.json` files
2. Extracts the top-level JSON key as the MCP server name via `python3 -c "import json; print(list(json.load(...)).keys()[0])"`
3. Skips disabled modules (resolved from `.devbot.jsonc` `disabled_modules`)
4. Checks if already registered via `grep -q "\"${mcp_key}\"" "${config_file}"`
5. Substitutes `__GPU_ENABLED__` placeholder with the actual boolean from `_devbot_get_bool("gpu_enabled")`
6. Merges into the project's opencode config using `merge_mcp_jsonc.py` (comment-preserving, returns INSERTED/SKIP_EXISTS/NO_MCP)
7. Falls back to `read_jsonc.py` + `jq` if no `mcp` section exists yet (NO_MCP case)

The `merge_mcp_jsonc.py` helper (196 lines at `src/_shared/merge_mcp_jsonc.py`) is a custom Python script that finds the `"mcp"` key in JSONC files via regex, then inserts entries with correct indentation before the closing `}`, preserving all `//` and `/* */` comments.
