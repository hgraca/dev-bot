---
date: 2026-05-17
keywords: ["opencode", "zod", "custom-tools", "schema", "crash"]
---

## Any external Zod schema in custom tool args crashes opencode's toJsonSchema — use args:{}

opencode's bundled `worker.js` uses Zod v4 internals (`_zod.def`) to convert tool parameter schemas to JSON Schema via `z.object(def.args)`. When a custom tool imports `@opencode-ai/plugin` and declares any `args` field using `tool.schema.*` (including `z.string()`, `z.enum()`, `z.array()`, `z.union()`), those schemas come from a separate Zod v4 instance. The cross-instance schema objects lack the expected internal structure, causing a crash at registration time: `TypeError: undefined is not an object (evaluating 'p.split')`. The crash happens before `execute()` is ever called. The only safe fix: use `args: {}` (empty object) so opencode wraps it as `z.object({})` with no external schemas. Document all parameters in the tool `description` string instead, and access them in `execute()` via `(rawArgs as any).field`. This is tracked as opencode issue #21155 and is unfixed as of v1.14.50. See [[global/opencode/20260412000000-06-opencodedistjsonc-contains-comments-never-use-jsonload.md]].
