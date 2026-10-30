---
date: 2026-10-30
keywords: ["shell", "awk", "pipefail", "sigpipe", "pipeline"]
aliases: ["awk exit SIGPIPE", "pipeline fails on match", "lookup dies silently"]
trigger-on: ["shell-pipeline-early-exit", "awk-early-exit"]
---

## An early `exit` in an awk stage kills the writer under `pipefail`

`git worktree list --porcelain | awk '… ; exit'` — the natural "stop at the first match" — makes
awk close the pipe while git is still writing. Git takes SIGPIPE and exits 141; with `set -o
pipefail` that becomes the pipeline's status, and under `set -e` the whole command dies with no
output at all. It is intermittent by size: output that fits the 64 KiB pipe buffer is written before
awk exits, so small repositories pass and large ones (many worktrees, many refs, long `git log`)
fail. A function called as `path="$(lookup …)"` then aborts the script and the caller reports
something unrelated, e.g. "nothing found".

Same family as `cmd | grep -q` under pipefail, and the fixes are the same shape: consume the whole
stream (drop the early `exit`, print the first match with a `done` flag), capture first
(`listing="$(cmd)"` then match on the variable), or use a here-string instead of a pipe.
