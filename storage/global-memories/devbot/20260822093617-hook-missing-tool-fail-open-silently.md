---
date: 2026-08-22
keywords: ["devbot", "hooks", "fail-open", "guards"]
trigger-on: ["hook-delegates-to-tool"]
---

## Hooks that delegate to a missing tools/ file silently fail-open

A hook that shells out to a `tools/` entry guarded by `if [[ ! -f "$TOOL" ]]; then exit 0; fi` silently no-ops when the tool file is missing or renamed — the hook stops doing its job with no error. Hit in `guards`: the claudecode hook referenced `tools/guards.ts`, which did not exist, so guards never ran under claudecode while the opencode hook (logic inlined) kept working. When a hook delegates to a tool, verify the tool file exists (assert its presence in a test and add a hook smoke test that exercises the block/deny path), don't trust fail-open to surface the breakage.
