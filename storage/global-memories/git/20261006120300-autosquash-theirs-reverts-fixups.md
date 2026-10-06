---
date: 2026-10-06
keywords: ["git", "rebase", "autosquash", "fixup", "theirs"]
trigger-on: ["git-autosquash-fixups"]
---

## `git rebase --autosquash -X theirs` silently reverts fixups — verify the tree hash

Fixups authored at a branch tip (against the final tree) often conflict when `--autosquash` replays them at their target commit, because the target state lacks the later commits' changes. Running the rebase with `-X theirs` to "auto-resolve" is a trap: during a rebase "theirs" is the commit being applied, so for the base `pick`s it silently prefers the old content — observed reverting several already-correct fixes and yielding a different final tree with no conflict reported. Do not reach for `-X theirs`. Resolve each conflict by taking the known-good content (e.g. `git checkout <pre-rebase-head> -- <file>`), `git rebase --continue`, and prove the rewrite with the tree hash: `git rev-parse <pre-rebase-head>^{tree}` must equal `git rev-parse HEAD^{tree}` before accepting it (`<pre-rebase-head>` is in the reflog / `ORIG_HEAD`).
