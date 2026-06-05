---
date: 2026-05-06
keywords: ["bun", "test"]
---

## `console.error()` not interceptable by bun test — use `process.stderr.write()` for testable error output

Bun's test runner (and the standard `process.stderr.write` monkey-patch pattern used in tests) does NOT capture output from `console.error()`. Tests that need to assert "exactly one stderr line was emitted" must monkey-patch `process.stderr.write` and the production code must call `process.stderr.write("[plugin] message\n")` directly — `console.error("[plugin] message")` won't be seen by the patched stderr. Hit during agent-communication Task 4 (commit `17b1138`) — ceiling-message test (L.2) failed with `console.error`, passed after switching to `process.stderr.write`. Rule for plugin code: when emitting a stderr line that production tooling AND tests need to see, prefer `process.stderr.write(`<msg>\n`)` over `console.error(<msg>)`. Trailing `\n` is required since `process.stderr.write` does not append one. See [[memories]].
