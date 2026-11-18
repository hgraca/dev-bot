---
date: 2026-11-18
keywords: ["git", "ls-files", "test-discovery", "untracked"]
aliases: ["test runner misses new tests", "git ls-files vs -r"]
---

## A `git ls-files`-driven test or asset discovery stops seeing untracked files

Replacing a filesystem walk (`-r dir/`) with `git ls-files` in a runner makes the set reproducible and skips editor scratch files — and silently stops collecting anything not yet `git add`ed. A test written and run before staging then simply does not execute, and the suite reports green: the worst possible failure mode, because the author believes their new test passed.

When you switch a discovery path to `git ls-files`, union it with `git ls-files --others --exclude-standard` for the local (authoring) path, and keep the tracked-only list for anything that must be reproducible across machines (CI, release slicing). Pin it with a test that asserts the collected set equals what git knows, so a future change to the discovery cannot quietly shrink coverage.
