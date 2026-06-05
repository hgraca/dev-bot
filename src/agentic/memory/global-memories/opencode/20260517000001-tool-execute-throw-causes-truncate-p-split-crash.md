---
date: 2026-05-17
keywords: ["opencode", "tool", "truncate", "execute", "error"]
---

## Unhandled throw from tool `execute()` causes Truncate crash "p.split is not a function"

When a custom tool's `execute()` function throws an unhandled exception, opencode's Truncate service receives `undefined` as the tool output and crashes with `undefined is not an object (evaluating 'p.split')` — because Truncate calls `p.split("\n")` on the return value to count lines. The error appears to originate from the tool itself, making the real cause (the unhandled throw) hard to trace. Common trigger: spreading an `undefined` array arg — `const cmd = ["bash", script, ...args.paths]` throws `TypeError` if `args.paths` is `undefined`, which escapes `execute()` and causes the tool runner to return `undefined` to Truncate. Fix: always return a string from `execute()`, never let it throw — guard array args defensively: `if (!args.paths) return "tool: 'paths' argument is required"; const paths = Array.isArray(args.paths) ? args.paths : [String(args.paths)]`. Discovered in `src/instructions/tools/tree/tree.ts` (commit 4bd7ce3), opencode v1.14.50.
