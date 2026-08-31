---
date: 2026-05-02
keywords: ["bun", "test", "mock", "esm"]
---

## Bun ESM static named imports cannot be mocked with `mock.module()`

When a module uses `import { readFileSync, existsSync } from "fs"`, Bun binds these named imports at module load time. Calling `mock.module("fs", ...)` after import has no effect on already-bound references. This makes fs mocking unreliable for plugins that use named imports.
Fix: Use real temporary files/directories instead of mocking fs. Create temp dirs with `mkdirSync`, write test fixtures with `writeFileSync`, clean up in `finally` blocks.
