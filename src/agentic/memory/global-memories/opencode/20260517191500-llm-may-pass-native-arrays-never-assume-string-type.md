---
date: 2026-05-17
keywords: ["opencode", "custom-tool", "args", "type-coercion"]
---

## LLMs may pass native JS arrays to custom tools — never assume string type

With `args: {}`, opencode passes tool arguments as-is from the LLM without type coercion. A parameter documented as a string may arrive as a native JS array (e.g. `paths: ["src", "lib"]`), a number, or null. Casting with `as string | undefined` does not coerce — `Array.isArray(rawVal)` check must come first, then `String(rawVal)` for all other non-null types. Pattern for any multi-value string param: `if (Array.isArray(rawVal)) use directly; else coerce with String(); then parse as JSON/comma/space-separated`. Never call `.split()` on an unverified value.
