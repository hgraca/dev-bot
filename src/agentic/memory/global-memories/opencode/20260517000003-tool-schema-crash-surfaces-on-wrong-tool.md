---
date: 2026-05-17
keywords: ["opencode", "custom-tools", "zod", "debugging"]
---

## A single tool with tool.schema in args poisons the entire tool registry — crash surfaces on wrong tool

When any one opencode custom tool has an external Zod schema in its `args` (even `z.string()`), the cross-instance `toJsonSchema` crash at registration time causes the error to surface on whichever tool the LLM happens to call first — not the broken tool. This makes diagnosis misleading: `search-memories` appeared to crash repeatedly even after being fixed, because `git-report`, `watermark-session`, and `format-md` still had `tool.schema` in their args. When debugging `p.split` crashes, audit every tool in `.opencode/tools/` for `tool.schema` usage, not just the one named in the error. See [[global/opencode/20260517000001-z-array-union-crashes-toJsonSchema.md]].
