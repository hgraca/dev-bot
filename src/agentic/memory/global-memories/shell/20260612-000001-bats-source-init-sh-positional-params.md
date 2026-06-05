---
date: 2026-06-12
keywords: ["shell", "bash", "bats", "testing", "source", "positional-parameters"]
---

## BATS test: sourcing init.sh leaks function arguments into PROJECT_DIR

When testing init.sh functions via BATS, sourcing an init.sh script that reads `$1` for PROJECT_DIR will pick up leaked positional parameters if called from inside a helper function. For example, `run _helper _run_inits` causes the init.sh to resolve `$1` = `_run_inits` and fail with "Directory '_run_inits' does not exist."

Fix: save function args to a local array, call `set --` to clear positional params before sourcing, then re-apply saved args after sourcing. Also override PROJECT_DIR after sourcing since init.sh will overwrite it with `$(pwd)`.
