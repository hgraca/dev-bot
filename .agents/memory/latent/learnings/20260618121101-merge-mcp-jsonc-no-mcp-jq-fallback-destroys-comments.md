---
date: 2026-06-18
keywords: ["devbot", "merge_mcp_jsonc", "JSONC", "jq", "NO_MCP"]
---

## merge_mcp_jsonc.py NO_MCP jq fallback destroys all JSONC comments

When opencode.jsonc exists but has no `"mcp"` section (dist template has none), `merge_mcp_jsonc.py` returned `NO_MCP` and the bash fallback in `_register_module_mcp` used `read_jsonc.py | jq` to create the section. This pipeline strips all `//` and `/* */` comments and reformats the entire file — destroying commented-out provider blocks, agent model overrides, and annotations permanently. The fix replaces the NO_MCP exit with text-based insertion that creates the `"mcp"` section before the last closing `}`, mirroring the same pattern in `merge_modules_jsonc.py` lines 143-184 (indentation detection, comma-separation logic, closing-brace insertion). The jq fallback branch in init.sh is removed entirely.
