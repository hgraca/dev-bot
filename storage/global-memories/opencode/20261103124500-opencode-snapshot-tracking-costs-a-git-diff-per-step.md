---
date: 2026-11-03
keywords: ["opencode", "snapshots", "performance", "git-diff"]
aliases: ["snapshot tracking", "undo snapshots", "tracking hash"]
trigger-on: ["opencode-snapshots", "opencode-performance"]
---

## opencode snapshot tracking runs a git diff over the whole worktree on every step

With `snapshots` enabled (the default), opencode records a filesystem snapshot by running `git ls-files --others --exclude-standard` and `git diff-files` against a private git dir with `--work-tree <project>` on every message/tool step — logged as `message=tracking`. On a large multi-repo workspace this is measurable: 7,357 tracked files cost ~0.17 s for `ls-files` plus ~1.0 s for `diff-files` per cycle, and one 7-day log held 17,993 `tracking` events. Set `"snapshots": false` in `opencode.jsonc` to remove the per-step cost; the trade-off is that undo/revert of file changes no longer works. The current key is `snapshots`; `snapshot` is the deprecated alias.
