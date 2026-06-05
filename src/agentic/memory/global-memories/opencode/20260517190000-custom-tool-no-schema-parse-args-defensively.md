---
date: 2026-05-17
keywords: ["opencode", "custom-tool", "args", "parsing"]
---

## Custom tools with args:{} receive no schema — parse all string args defensively

When a custom opencode tool uses `args: {}` (required to avoid Zod `toJsonSchema` crash), the LLM receives no parameter schema. It will pass multi-value string arguments in whatever format feels natural: JSON array `'["a","b"]'`, comma-separated `'a,b'`, or space-separated `'a b'`. Tools must handle all three formats. Pattern: try `JSON.parse` first (array check), then split on commas if present, then split on whitespace if multiple tokens, then treat as single value. Apply this to any tool parameter that logically accepts multiple values.
