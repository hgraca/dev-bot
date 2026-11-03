---
date: 2026-11-03
keywords: ["opencode", "snapshots", "dist-template", "performance"]
aliases: ["snapshot tracking", "undo revert"]
see: ["learnings/20261103124502-write-jsonc-from-dist-is-seed-once.md"]
---

## opencode snapshots are disabled by default in the dist template

`src/harnesses/opencode/opencode.dist.jsonc` now ships `"snapshots": false`, and the dev-bot project's own `opencode.jsonc` was set to match. Rationale: snapshot tracking runs a git diff over the whole worktree on every message/tool step (~1.2 s per cycle over 7,357 files on this workspace), and undo/revert of file changes is not used here. The default is guarded by a test in `src/harnesses/opencode/tests/dist_config_tests.bats`; because `_write_jsonc_from_dist` is seed-once, existing projects keep their current value and must be changed individually.
