---
date: 2026-09-02
keywords: ["shell", "set -e", "errexit", "and-list", "trap"]
trigger-on: ["bash-set-e-trailing-and-list"]
---

## set -e fires on a failing && list when it is the function's last statement

A bare `[[ cond ]] && action` used as the FINAL statement of a function exits the script under `set -euo pipefail` when the condition is false — errexit treats the failing last command of the AND-list (or of the function) as fatal. Symptom: a script dies silently right after a call with no trace of an error inside the function (guards like `2>/dev/null || true` hide the real cause). Fix: use an `if [[ ... ]]; then ...; fi` block for any trailing conditional, not `[[ ]] && cmd`. Reproduced in dev-bot's `_prune_stale_*` helpers (2026-09-02).
