---
date: 2026-10-27
keywords: ["shell", "pipefail", "grep", "sigpipe", "github-actions"]
trigger-on: ["shell-pipeline-condition", "pipelines-in-ci"]
---

## `cmd | grep -q` fails on a match under `pipefail`

GitHub Actions' default Linux shell runs bash with `-eo pipefail` (not just `-e`). `grep -q` exits
the moment it matches, the writer then takes SIGPIPE, and `pipefail` reports the pipeline as failed
— so `if printf '%s' "$x" | grep -qF "$needle"; then` takes the *failure* branch exactly when the
needle is present. It is intermittent and not gated on size: a two-line value flaked on CI (the
writer only sometimes loses the race to grep's early exit), while pushing the value past the 64 KiB
pipe buffer turns it into a deterministic repro. With a multi-line value the *first* entry is the
one that flakes — the last line never does, because grep has to read it to match it. Avoid the
pipeline —
`if grep -qF "$needle" <<< "$x"; then` — or capture first (`out="$(cmd)"; grep -q ... <<< "$out"`).
The same trap affects `git log --format=%s | grep -q` assertions in test suites, where it produces
a random 1-in-N flake rather than a consistent failure.
