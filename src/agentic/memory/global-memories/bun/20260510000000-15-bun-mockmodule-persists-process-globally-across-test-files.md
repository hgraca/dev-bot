---
date: 2026-05-10
keywords: ["bun", "test", "mock"]
---

## bun `mock.module()` persists process-globally across test files

**Symptom**: A test file that calls `mock.module("fs", () => ({ readFileSync: ... }))` contaminates _every other test file_ in the same `bun test` run. Symptoms in victim files: `readFileSync is not a function`, `existsSync is not a function`, ENOENT on paths that don't exist, or silent wrong-data reads. Tests pass in isolation, fail in the full suite, and the failure depends on file load order. **Cause**: bun's module cache is process-global. `mock.module()` replaces the cached module for the rest of the process; `mock.restore()` does NOT undo `mock.module()` (it only restores `mock()` function spies). `afterAll(() => mock.restore())` is a placebo. The unreleased `mock.restoreModule()` from PR #25844 would fix this, but is not in 1.3.13. **Fix**: at the contaminator site, capture the real module before mocking and have the factory fall through to real bindings for any path/key the test doesn't explicitly override:

```ts
import * as _realFs from "fs";
const _realRead = _realFs.readFileSync;
mock.module("fs", () => ({
  ..._realFs, // spread all real bindings
  readFileSync: (path, opts) => (_readMap.has(path) ? _readMap.get(path) : _realRead(path, opts)),
  // ...other overrides discriminate similarly
}));
```

For plugins that read a single sentinel path, discriminate by path suffix (e.g. `.ai/devbot/devbot.jsonc`) and fall through for everything else. **Confirmed 2026-05-10**: applied to `tests/plugins/active-work-context.test.ts` and `tests/plugins/dedupe.test.ts`; full suite went from 28 cross-contamination failures to 0. **Rule**: any `mock.module()` call in this codebase MUST spread the real module and provide fall-through for unmocked operations. Never assume `afterAll(mock.restore)` cleans up — it doesn't. See [[patterns]] "capture-real-module-before-mock".

**Refinement 2026-05-10 (later same day)**: The "discriminate by path suffix" advice above is **too broad and leaks**. Suffix matches like `path.endsWith(".ai/devbot/devbot.jsonc")` match ANY test's per-temp-dir `.ai/devbot/devbot.jsonc` file (other plugins like `tool-stats.js` write their own). Symptom: `tool-stats.test.ts` ran after a dedupe test got a stub `{"some_enabled": false}` injected into its own temp config, causing 3 cross-test failures that only appeared in file-order combinations. **Correct fix**: compute the EXACT absolute path the contaminator's own plugin reads at module load time and compare with `===`, not `endsWith`. Example:

```ts
const _PLUGIN_CONFIG_PATH = join(process.cwd(), ".ai", "devbot", "devbot.jsonc");
if (path === _PLUGIN_CONFIG_PATH) {
  /* stub */
} else {
  return _realRead(path, enc);
}
```

**Also**: mock BOTH `"fs"` AND `"node:fs"` explicitly with the same factory, even if Bun's cache unifies them. The plugin under test imports from `"node:fs"` but victim plugins (e.g. `tool-stats.js`) import from `"fs"`. Mocking only one side leaves the other's cache entry as whatever the previous test file installed. Confirmed 2026-05-10 on `tests/plugins/dedupe.test.ts`: dual-mock + exact-path discriminator brought `bun test` from 240 pass/4 fail/1 error to 243 pass/0 fail/0 error.

**Refinement (2026-05-10, second-order contamination)**: a path-_suffix_ discriminator like `path.endsWith(".ai/devbot/devbot.jsonc")` is **TOO BROAD** — it matches any victim test's tmpdir-rooted `<tmp>/.ai/devbot/devbot.jsonc`, returning the contaminator's stub JSON and silently corrupting the victim's reads. Symptom seen: `tool-stats.test.ts` wrote `{"project_name": "..."}` to its tmp devbot.jsonc, but read back `{"some_enabled": false}` (dedupe test's stub) → fell back to `"unknown"` project name. **Fix**: discriminate by **exact absolute path** computed once as a module-level constant: `const _PATH = join(process.cwd(), ".ai", "devbot", "devbot.jsonc")` and check `path === _PATH`. Suffix matches are unsafe whenever multiple tests use the same relative directory layout under different roots.

**Second refinement (2026-05-10, fs vs node:fs)**: bun's module cache unifies `"fs"` and `"node:fs"` resolution, so mocking only `"node:fs"` _also_ affects modules that `import from "fs"` — but the contaminator's spread/fall-through only captures the binding the contaminator imported. Safer pattern: capture **both** `import * as _realFsNode from "node:fs"` AND `import * as _realFsBare from "fs"`, install **both** mocks explicitly with the same factory shape. Other test files in this repo already use the bare `"fs"` form (e.g. `active-work-context.test.ts`); dual-mocking is the canonical pattern. Applied to `tests/plugins/dedupe.test.ts` (commit after planning-iter on 2026-05-10).
