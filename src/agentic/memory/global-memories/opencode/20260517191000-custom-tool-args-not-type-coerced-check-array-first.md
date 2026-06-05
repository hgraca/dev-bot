---
date: 2026-05-17
keywords: ["opencode", "custom-tool", "args", "type-coercion"]
---

## Custom tool args are not type-coerced — never assume string, always check Array.isArray first

With `args: {}`, opencode passes whatever the LLM sends without any type coercion. A parameter declared as `string` in the description may arrive as a native JS array, a number, or undefined. Casting with `as string | undefined` does not coerce — it only satisfies TypeScript. The safe pattern: check `Array.isArray(val)` first, then `String(val)` to coerce, never assume `.split()` is available. This applies to every parameter in every custom tool using `args: {}`.
