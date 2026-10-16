---
date: 2026-10-16
keywords: ["shell", "testing", "bats", "lifecycle-script"]
---

## A test that greps a script never runs it

Two lifecycle scripts (`install.sh`, `update.sh`) shipped with a `DEV_BOT_ROOT` off-by-one that made both abort on the first `source` — and passed CI, because their tests only `grep`ped the file for expected strings. Text assertions cannot catch a script that fails to execute: a wrong relative-path depth, a missing sourced file, or a bad shebang all leave the grep green while the script dies. Any lifecycle or provisioning script needs at least one **execution** test — run it with external commands stubbed (e.g. a no-op `npm` on `PATH`) and `assert_success` — so a script that cannot start fails the suite instead of shipping.
