---
date: 2026-05-17
keywords: ["opencode", "tool", "schema", "union", "crash"]
---

## tool.schema.union([string(), array(string())]) crashes opencode's schema converter

When a custom tool (`.ts` file under `.opencode/tools/`) declares an argument with `tool.schema.union([tool.schema.string(), tool.schema.array(tool.schema.string())])`, opencode's internal JSON-Schema converter crashes at tool-registration time with `undefined is not an object (evaluating 'p.split')`. The crash happens before `execute()` is ever called, so the tool silently fails for every invocation. Fix: replace the union with `tool.schema.array(tool.schema.string())` only — the LLM can always pass a single-element array, eliminating the union and the crash. Applied to `search-memories.ts` on 2026-05-17 (commit 56b5778).
