---
date: 2026-06-11
keywords: ["devbot", "jsonc", "mcp", "read_jsonc", "jq", "comments"]
---

## JSONC comments destroyed by read_jsonc.py | jq pipeline

When using `read_jsonc.py | jq > tmp && mv tmp config.jsonc` to modify a JSONC file, all `//` and `/* */` comments are permanently lost. `read_jsonc.py` strips comments during parsing, and `jq` outputs plain JSON with no comment support.

This silently destroys user-edited comment blocks in `opencode.jsonc` including:

- Commented-out agent provider blocks (opencode free, cortecs, litellm, deepseek)
- Inline annotations and configuration notes
- Temporarily disabled sections

The fix for the devbot init MCP registration was `merge_mcp_jsonc.py` (`src/_shared/merge_mcp_jsonc.py`) — a Python script that uses text-based brace matching on the raw file content to insert MCP entries while preserving all comments. Key design:

- Parse the file as text, not JSON
- Skip strings and comments when brace-matching to find correct insertion point
- Determine indentation from the mcp section's existing formatting
- Fall back to the `read_jsonc.py | jq` method only when no `mcp` section exists yet (one-time comment loss unavoidable for initial creation)
