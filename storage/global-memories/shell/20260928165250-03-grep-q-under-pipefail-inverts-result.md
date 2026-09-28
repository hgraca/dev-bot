---
date: 2026-09-28
keywords: ["shell", "pipefail", "grep", "sigpipe", "set -e"]
trigger-on: ["pipefail-with-early-exit-readers"]
---

## `grep -q` in a pipeline under `pipefail` can invert the result

With `set -o pipefail`, a pipeline like `producer | grep -q PATTERN` reports failure even when the pattern **matches**: `grep -q` exits at the first match, the producer keeps writing into a now-full pipe, takes SIGPIPE (exit 141), and `pipefail` surfaces that as the pipeline's status — so an `if` treats a present value as absent. It needs the producer's output to exceed the ~64 KiB pipe buffer (e.g. `cat`ing a 470 KB file) to trigger, which is why it looks intermittent and is easy to dismiss. Fix: capture first, then match — `out="$(producer 2>/dev/null || true)"` followed by `grep -q PATTERN <<<"$out"`. Verified on the same input: the direct pipeline reads NOMATCH while capture-then-match reads MATCH.
