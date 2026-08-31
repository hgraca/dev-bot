---
date: 2026-06-15
keywords: ["shell", "bash", "bats", "testing", "path", "source", "dirname"]
---

## BATS: PATH must include system dirs when sourcing module scripts

When testing module scripts like `functions.sh` in BATS with a custom PATH (e.g. to shadow a binary), setting `PATH` to an empty directory causes `source "${MODULE_DIR}/functions.sh"` to fail because `dirname` and `pwd` are external utilities (usually at `/usr/bin/dirname` and `/bin/pwd`). The error is silent — `source` fails with "dirname: command not found" and the test appears to work but produces no output.

Fix: use `export PATH="/usr/bin:/bin"` rather than `PATH="${emptydir}"` when the mock needs to shadow a single binary while keeping system utilities available.
