---
date: 2026-08-07
keywords: ['javascript', 'react', 'setState', 'race']
trigger-on: ['react-setstate-persistence', 'react-state-save']
---

## React setState race condition when persisting to backend

React state updates via `setState` are batched asynchronously. A function called immediately after `setState` that reads from the same state variable will see the **old** value. To persist data to an API after a state change, pass the new values as explicit arguments instead of reading from state. Pattern: `saveToDb(newStatuses, newReports)` where the function uses `newStatuses?.[id] ?? stateStatuses[id] ?? default` — explicit overrides take precedence, falling back to current state only when no override is provided.
