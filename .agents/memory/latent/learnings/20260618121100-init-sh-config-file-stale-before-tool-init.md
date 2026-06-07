---
date: 2026-06-18
keywords: ["devbot", "init.sh", "config_file", "MCP", "opencode.jsonc"]
---

## config_file variable stale when opencode.jsonc created by tool-init loop

In `bin/init.sh`, `config_file` is captured at lines 286-294 before the tool-init loop runs. When opencode.jsonc doesn't exist yet, `config_file=""`. The tool-init loop (src/tools/opencode/init.sh) creates opencode.jsonc via `_write_opencode_config`, but `config_file` is never re-detected. The module loop then passes the empty `config_file` to `_register_module_mcp`, which short-circuits at the `-z "${config_file}"` check — all MCP registrations silently skip.

Fix: Add a re-detection block after the tool-init `done` that checks `[[ -z "${config_file}" && -f "${PROJECT_DIR}/opencode.jsonc" ]]` and re-sets both `config_file` and `config_name`. Note that plugins don't have this problem because `_upsert_opencode_plugin` uses the hardcoded path `${PROJECT_DIR}/opencode.jsonc` instead of the variable.
