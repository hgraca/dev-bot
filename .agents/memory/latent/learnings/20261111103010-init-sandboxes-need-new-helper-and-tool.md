---
date: 2026-11-11
keywords: ["devbot", "bats", "init", "sandbox", "stub"]
see: ["learnings/20260823103101-bats-stubs-mirror-helper-surface.md"]
---

# Init test sandboxes need the new helper *and* its tool copied

`bin/tests/init_or_reinit_tests.bats`, `init_reset_path_tests.bats` and `init_dirty_flag_tests.bats` source a stripped `bin/init.sh` against a fake `src/_shared/functions.sh`, so they see only the helpers the stub defines plus the few extracted verbatim with `awk '/^_helper\(\) \{/,/^\}/'`. Moving `_migrate_workspace_config` into `functions.sh` broke them twice over: the helper was absent (init exited 127 mid-run, and CI's `test-slice` failed while the local targeted runs passed), and once added it invoked `python3 $DEV_BOT_ROOT/src/_shared/migrate_workspace_config.py`, which the sandbox never copied — and a missing migration tool deliberately returns non-zero.

Two rules when adding or moving a `functions.sh` helper that `init.sh` calls: add the `awk` extraction line to every init sandbox, and copy the python tools it shells out to (`read_jsonc.py`, the migration script) into the sandbox's `src/_shared/`. Run all of `bin/tests/init_*.bats` — not just the sandbox being edited — before pushing; CI runs the full set and will catch what a single file does not.
