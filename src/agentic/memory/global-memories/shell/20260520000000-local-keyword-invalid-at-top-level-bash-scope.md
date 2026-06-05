---
date: 2026-05-20
keywords: ["shell", "bash", "local", "scope"]
---

## `local` is invalid at top-level bash scope — use plain assignment

The `local` keyword is only valid inside a function body. Using `local var` at the top level of a script (outside any function) causes a syntax error: `local: can only be used in a function`. When writing module scripts like `update.sh` or `install.sh` that run at top level, declare variables with plain assignment (`var=value`) rather than `local var; var=value`. This is a common mistake when copying patterns from function bodies into script-level code.
