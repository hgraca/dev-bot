---
date: 2026-09-10
keywords: ["opencode", "stats", "sqlite", "tool-usage", "opencode-db"]
trigger-on: ["opencode-stats", "opencode-db-query", "tool-usage-report"]
---

## opencode tool usage lives in opencode.db; the `opencode stats` CLI truncates tool names

`opencode stats` reports token/cost/tool statistics but truncates tool names to 16 chars + `..` (e.g. `devbot-tools_sea..`) and has no `--format json`, so it cannot drive reliable MCP-server aggregation. The authoritative source is the SQLite DB at `~/.local/share/opencode/opencode.db`, opened read-only (`sqlite3 "file:<path>?mode=ro"`, or Python `sqlite3.connect("file:...?mode=ro", uri=True)`). Tool calls are `part` rows whose `data` JSON has `"type":"tool"` and a full, untruncated `"tool"` name (plus `state.input` for the arguments); `"type":"step-finish"` rows carry the step's `cost` and `tokens.total`, which must be split across the tools that step invoked. The `session` table has `directory`, `time_created`, and pre-aggregated `cost`/`tokens_*` columns.

Performance trap: a bare `WHERE json_extract(data,'$.type')='tool'` full-scans a multi-GB `part` table (~35 s). Joining `session` and filtering on `s.directory = ?` (and `p.time_created >= cutoff`) drops it to ~3–4 s. Always scope by directory/time before extracting JSON.
