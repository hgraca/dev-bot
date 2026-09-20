---
date: 2026-09-10
keywords: ["shell", "set -e", "pipefail", "command-substitution"]
trigger-on: ["bash-errexit-rc-capture", "bash-pipefail-empty-glob"]
---

## Capturing `$?` and empty-glob pipelines under `set -euo pipefail`

Under `set -e`, `cmd; rc=$?` never reaches the assignment when `cmd` returns non-zero — the shell exits first. Use `cmd || rc=$?` (or an `if cmd; then …`), which also keeps `errexit` from firing. Separately, with `pipefail` a command substitution like `x="$(ls dir/*.json | head -1)"` fails the whole assignment when the glob matches nothing (`ls` exits non-zero), aborting the script; append `|| true` inside the substitution (`x="$(ls … | head -1 || true)"`) or replace `ls` with a glob loop (`for f in dir/*.json; do [[ -f "$f" ]] || continue; …`). Both bit a non-fatal helper that was supposed to tolerate missing pieces.
