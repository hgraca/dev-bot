---
date: 2026-08-23
keywords: ["shell", "bats", "test", "mv", "teardown"]
trigger-on: ["bats-mv-source-file"]
---

## BATS tests must not mv a real source file to simulate absence

A test that simulates a missing file by `mv`-ing a tracked source file away and restoring it after the assertions leaves the file deleted if an assertion fails (the restore `mv` is skipped), and a `find tmp.* -exec rm` teardown then wipes the moved copy — silently deleting a tracked source file from the working tree. Observed in dev-bot `search-memories_tests.bats` ("python script missing" test): it `mv`-ed `search-memories.py` to a `$FIXTURES/tmp.*` path, ran the wrapper, then `mv`-ed it back — on failure the `.py` vanished. Fix: don't touch the real file — override `PATH`, point the tool at a nonexistent path, or use a mock; otherwise guarantee restore with a teardown trap (`trap '<restore>' EXIT`) so it runs even on assertion failure. Symptom: a tracked source file shows as deleted in `git status` with no obvious cause.
