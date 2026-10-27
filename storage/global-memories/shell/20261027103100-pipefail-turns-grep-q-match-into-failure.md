---
date: 2026-10-27
keywords: ["shell", "pipefail", "grep", "sigpipe", "github-actions"]
trigger-on: ["shell-pipeline-condition", "pipelines-in-ci"]
---

## `cmd | grep -q` fails on a match under `pipefail`

GitHub Actions' default Linux shell runs bash with `-eo pipefail` (not just `-e`). `grep -q` exits
the moment it matches, the writer then takes SIGPIPE, and `pipefail` reports the pipeline as failed
— so `if printf '%s' "$x" | grep -qF "$needle"; then` takes the *failure* branch exactly when the
needle is present. It is intermittent: it only bites once the writer's output exceeds the pipe
buffer, which is why small values pass in tests and large ones fail in CI. Avoid the pipeline —
`if grep -qF "$needle" <<< "$x"; then` — or capture first (`out="$(cmd)"; grep -q ... <<< "$out"`).
The same trap affects `git log --format=%s | grep -q` assertions in test suites, where it produces
a random 1-in-N flake rather than a consistent failure.
