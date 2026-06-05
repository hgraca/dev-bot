---
date: 2026-06-17
keywords: ["shell", "bash", "trap", "local", "set-u"]
---

## local variable with trap EXIT causes unbound variable error under set -euo pipefail

When a function declares `local tmpdir=$(mktemp -d)` and sets `trap 'rm -rf "${tmpdir}"' EXIT`, the single-quoted trap defers expansion of `${tmpdir}` until trap execution (script exit). By then the function has returned, the `local` variable is out of scope, and `set -u` triggers `tmpdir: unbound variable`. Fix: do not use `local` for variables referenced by traps — keep them global, or clean up explicitly before return (`rm -rf "${tmpdir}"; trap - EXIT`). Single-quoted trap strings do not capture the value at definition time; they re-evaluate at trap time. Combined with `set -u`, this is a silent bug that surfaces only when an handler or ERR trap fires after the function scope ends.
