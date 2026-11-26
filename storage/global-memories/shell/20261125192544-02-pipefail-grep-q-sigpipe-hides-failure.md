---
date: 2026-11-25
keywords: ["shell", "pipefail", "grep", "sigpipe", "set -e"]
aliases: ["grep -q breaks pipefail", "rollback silently skipped", "validation guard fails open"]
---

## `producer | grep -q` reports failure under `pipefail` even on a match

`grep -q` exits the moment it matches, closing the pipe. If the producer still has output to write it dies of SIGPIPE (141), and `set -o pipefail` makes the **pipeline** report 141 — so `if producer | grep -q pattern; then` takes the false branch precisely when the pattern matched early. Guards written this way fail open: a validate-and-roll-back step is skipped, the broken result is kept, and the code reads correctly in review.

Capture the output instead: `out=$(producer 2>&1 || true); if [[ "$out" == *pattern* ]]; then …`. The same trap applies to `cmd | head -1` and any consumer that stops reading early. Related `set -e` subtlety: in `cmd && action`, a failing `cmd` is not the last command of the list, so the shell does not exit there — but the list still returns non-zero, which aborts an enclosing function or script when it is the last command of one. Prefer an explicit `if cmd; then action; fi`.
