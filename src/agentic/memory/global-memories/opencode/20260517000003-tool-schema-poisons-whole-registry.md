---
date: 2026-05-17
keywords: ["opencode", "custom-tools", "zod", "debugging"]
---

## A single tool with tool.schema in args poisons the whole registry — crash appears on wrong tool

When any opencode custom tool has an external Zod schema in its `args` (even `z.string()`), the `toJsonSchema` crash at registration time corrupts the entire tool registry for that session. The error surfaces on whichever tool the LLM happens to call first — not the broken tool. This makes diagnosis misleading: `search-memories` appeared to crash even after being fixed, because `git-report`, `watermark-session`, and `format-md` still had `tool.schema` in their args. Fix: audit every tool file for `tool.schema` usage with `grep -rn "tool\.schema" src/instructions/tools/` and ensure all use `args: {}`. See [[global/opencode/20260517000001-z-array-union-crashes-toJsonSchema.md]].
