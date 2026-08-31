---
date: 2026-08-11
keywords: ['react', 'typescript', 'render-prop', 'type-casting']
trigger-on: ['render-prop', 'Record-string-unknown', 'hotel-table']
---

## Record<string, unknown> render props need explicit type casts

When a React component accepts a render prop typed as `(item: Record<string, unknown>) => ReactNode`, accessing nested properties like `item.stars` requires explicit casting (`as number`) before use in operations like `Math.min()` or `String.repeat()`. TypeScript's `unknown` type does not narrow automatically — `item.stars!` (non-null assertion) is insufficient for typed operations. Pattern: extract to typed local variable (`const s = h.stars as number | null | undefined`) at the top of the render function.
