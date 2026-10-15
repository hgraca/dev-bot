---
date: 2026-10-13
keywords: ["testing-library", "cleanup", "vitest", "globals"]
aliases: ["renders leak between tests", "Found multiple elements with the role"]
trigger-on: ["vitest-setup", "testing-library-setup"]
---

## Testing Library's auto-cleanup needs vitest `globals` — without it renders leak between tests

`@testing-library/react` only registers its `afterEach(cleanup)` automatically when a global `afterEach` exists. With vitest's `globals: false` (the default when using explicit `import { describe, it } from "vitest"`), nothing registers cleanup, so every `render()` accumulates in `document.body` and a later query can match an earlier test's tree.

The failure is misleading rather than obvious: it surfaces as `TestingLibraryElementError: Found multiple elements with the role "main"` in whichever test happens to use a query that is not already unique — often a test that has nothing to do with the accumulating one. Existing tests can pass for a long time because their text queries happen to stay unique.

Fix: call cleanup explicitly from the shared setup file — `import { cleanup } from "@testing-library/react"; import { afterEach } from "vitest"; afterEach(cleanup)` — or set `globals: true`. Asserting on a landmark role (`main`, `banner`, `contentinfo`) is a reliable way to notice leakage.
