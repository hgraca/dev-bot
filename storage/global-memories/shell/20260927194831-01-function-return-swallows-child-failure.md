---
date: 2026-09-27
keywords: ["shell", "set-e", "return-code", "error-handling"]
trigger-on: ["bash-function-error-propagation"]
---

## A wrapper function's `else _error; fi` branch returns 0, swallowing the child's failure

In bash a function whose last executed statement is an `echo`-only helper — e.g. `_error() { echo "ERROR: $*" >&2; }` — returns 0. So `if bash child.sh; then _ok "..."; else _error "child failed"; fi` leaves the wrapper function's exit status at 0, and every caller reads the child's failure as success. Seen live: `bin/reinit.sh::_reinit_project` swallowed a failing `init.sh`, so `reinit.sh` exited 0 and the auto-reinit caller printed "✔ Reinit complete" while the wiring was half-built. `set -e` does not help — the command sits in an `if` condition, an explicit `-e` exemption. Fix: `return 1` explicitly in the failure branch, propagate a non-zero exit from the script's `main`, and accumulate across loops (`_reinit_project ... || failed=1`) so one failure is not masked by another project's success. Rule: a helper that only prints is not a failure signal — failure must be a non-zero return/exit.
