---
date: 2026-05-20
keywords: ["shell", "bash", "local", "set -euo pipefail", "init.sh"]
---

## `local` keyword causes exit 1 when used outside a function in bash scripts

In bash scripts running under `set -euo pipefail`, using `local varname=...` at the top level of the script (outside any function) is a syntax error — bash prints `local: can only be used in a function` and exits with code 1. This is a silent failure: the script appears to run (earlier steps succeed) but exits unexpectedly at the `local` line. The fix is to drop `local` and use a plain assignment (`varname=...`) at script top-level. This trap is easy to hit when copying variable declarations from function bodies into module init scripts.
