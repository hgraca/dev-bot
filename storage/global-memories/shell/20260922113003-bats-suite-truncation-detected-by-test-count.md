---
date: 2026-09-22
keywords: ["shell", "bats", "pty", "test-suite", "truncation"]
trigger-on: ["bats-suite-truncated-run"]
---

## A long bats suite can be silently truncated by a session timeout — compare counts to detect it

Running a large bats suite through a PTY (here `bats -T -r src/ bin/`, ~1300 tests) can outlive the session timeout: the harness stops the run mid-suite and can still report a benign `Exit Code: 0`, which reads as a pass. Detect truncation by comparing the `ok N` lines the run emitted against the declared test count — `grep -rhE '^[[:space:]]*@test' --include='*.bats' src/ bin/ | wc -l`. A mismatch (621 reported against 1307 declared) proves the suite never finished, however clean the exit code looks. Fix the run rather than the reading: bound it with coreutils `timeout -k 5 <N> bats ...` so a genuine overrun exits non-zero, or scope the run to the module the change touches and verify the rest separately.
