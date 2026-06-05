---
date: 2026-05-17
keywords: ["opencode", "tool schema", "union", "zod", "crash"]
---

## tool.schema.union([string(), array(string())]) crashes opencode's schema converter

When a custom tool (`.ts` file under `.opencode/tools/`) declares an arg with `tool.schema.union([tool.schema.string(), tool.schema.array(tool.schema.string())])`, opencode's internal tool-schema-to-JSON-Schema converter throws `undefined is not an object (evaluating 'p.split')` at tool registration time — before `execute()` is ever called. The crash silently swallows the tool call and the LLM sees an error. Fix: replace the union with `array(string())` only; the LLM can always pass a single-element array, so no functionality is lost. See fix in `src/instructions/tools/search-memories/search-memories.ts` (commit 56b5778).
