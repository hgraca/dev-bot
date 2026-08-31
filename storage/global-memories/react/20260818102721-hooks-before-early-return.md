---
date: 2026-08-18
keywords: ["react", "hooks", "rules-of-hooks", "useState", "early-return"]
trigger-on: ["react-hook-order", "rules-of-hooks-early-return"]
---

## Call hooks before any early return in a component

In `CompareMatrixTable.tsx` a `useState` for `hiddenHotelIds` was initially declared after the `if (matrix.length === 0)` early return. That violates the Rules of Hooks: hook calls must run unconditionally in the same order every render. If a component renders once with an empty `matrix` (hook skipped) and later with a non-empty `matrix` (hook called), the hook count changes between renders and React throws "Rendered fewer hooks than expected". Fix: hoist every `useState`/`useEffect` above any early `return` in the component body, deriving values from props after the hook declarations. The guard itself can stay as an early return; it must simply come after all hooks.
