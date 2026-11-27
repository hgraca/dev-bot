---
date: 2026-11-26
keywords: ["mcp", "json", "stderr", "parse"]
aliases: ["mcp output not json", "json parse line 2 col 35", "trailing stderr block"]
---

## MCP tools that return text append a `[stderr]` block after the JSON

Several MCP servers return their result as a plain string rather than a structured object, and the wrapper appends diagnostics after the payload — `kctl-*` ends every call with `[stderr]\nkubectl context: …`, and the SigNoz search tools (`signoz_search_logs`, `signoz_search_traces`) return a JSON document with trailing content. `JSON.parse(response)` then throws `Unable to parse JSON string (line 2, col 35)`, which looks like a malformed payload and sends you chasing the wrong thing.

Parse by trimming to the last closing brace first — `JSON.parse(r.slice(0, r.lastIndexOf("}") + 1))` — and read any `[stderr]` prefix separately instead of discarding it, since that is where the tool reports the context it actually ran against. When the shape is unknown, `typeof result === "string"` is the cheap check before parsing.
