---
date: 2026-05-17
keywords: ["opencode", "custom-tool", "args", "multi-value"]
---

## Custom tools with args:{} must parse all natural multi-value string formats

When a custom tool uses `args: {}` (required to avoid Zod `toJsonSchema` crash), opencode shows no parameter schema to the LLM. The LLM then passes multi-value parameters in whatever format feels natural: JSON array `'["a","b"]'`, comma-separated `'a,b'`, or space-separated `'a b'`. A tool that only handles one format will silently fail for the others. The fix is to parse all three formats in order: (1) try `JSON.parse` — if it yields an array, use it; (2) if the string contains a comma, split on commas; (3) if the string contains spaces and looks like multiple tokens, split on whitespace; (4) otherwise treat as a single value. Apply this pattern to every string parameter that may accept multiple values.
