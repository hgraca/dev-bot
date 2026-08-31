---
date: 2026-06-15
keywords: ["shell", "set -e", "return", "exit-code"]
---

## Bare `return` propagates last command's exit code, killing script under set -e

In bash functions, `return` without an argument returns the exit status of the last executed command. When used as an early-exit guard like `[[ -d "${dir}" ]] || return`, a missing directory causes `return` to propagate exit code 1. If the caller does NOT wrap the function in `if`/`while`/`||`/`&&`, `set -e` kills the script. Always use explicit `return 0` for intentional early exits that are not errors.
