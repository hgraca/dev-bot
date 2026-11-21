---
date: 2026-11-20
keywords: ["shell", "errexit", "set -e", "failure handling"]
aliases: ["set -e disabled in conditionals", "unchecked mv reads as success", "errexit scope"]
trigger-on: ["shell-error-handling", "set-e-scope"]
---

## `set -e` is off inside `if`/`&&`/`||` — an unchecked command reads as success

Under `set -e`, every command in a conditional context runs with errexit disabled: the body of `if ! cmd; then …; fi`, both sides of `&&` and `||`, and — the trap — **every command inside a function invoked that way** (`if f`, `f || true`, `f && g`). A shared helper called as `helper || warn` therefore continues after a failed `mv`, `cp`, `sed` or `curl` and reaches its trailing `_ok "stored …"`, returning 0: the caller believes the write landed and moves on. Guard each mutation explicitly — `if ! mv "${staged}" "${file}"; then rm -f "${staged}"; return 1; fi` — rather than assuming errexit covers it, and treat any "success" message printed after a fallible command as unverified until that command's status is checked.
