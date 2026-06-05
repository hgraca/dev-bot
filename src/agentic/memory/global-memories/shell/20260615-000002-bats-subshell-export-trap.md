---
date: 2026-06-15
keywords: ["shell", "bash", "bats", "testing", "subshell", "export"]
---

## BATS: `$()` subshell loses exports — helper functions must inline or use env vars

When a BATS helper function uses `$()` (command substitution) to capture a return value, any `export` statements inside the subshell do NOT propagate to the parent test shell. This causes silent failures: environment variables like `PATH`, `HOME`, `DEV_BOT_ROOT` appear set inside the helper but are unset after the function returns.

Fix options: (a) inline environment setup directly in each test body (exports happen in the test's own shell), or (b) have the helper echo export commands and use `eval "$(_setup_env)"`, or (c) use a convention where the helper sets global variables rather than using `$()` capture. Option (a) is simplest and most debuggable.
