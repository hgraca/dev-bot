---
date: 2026-10-03
keywords: ["make-test", "pty", "concurrency", "exit-marker"]
---

# A concurrent `make test` makes a PTY run time out, and a reaped PTY's exit code is untrustworthy

Running the full suite in a PTY while another agent ran `make test` on the same checkout (load
average 19.6) produced a run that hit `timeoutSeconds`, was killed mid-BATS, and reported a
contradictory `Timed Out: yes` alongside `exit 0` and a truncated buffer ending on a BATS `ok` line.
A completed suite ends with the Python phase (~2153 lines ending in `OK`), so anything ending on a
BATS line did not finish — that was not a pass.

Two rules fall out:

- Before concluding a PTY `make test` hung, check for a concurrent suite with
  `ps -eo pid,etime,cmd | grep 'make test'`. Two `--jobs 8` BATS runs on one repo contend; wait for
  the other to finish rather than reshuffling this one (the suite is I/O-contention-bound — see
  `learnings/20260920164034-01-test-suite-is-io-contention-bound.md`).
- When a PTY run's result must be trusted, do not rely on the exit notification or buffer alone:
  append an independent marker —
  `make test </dev/null; rc=$?; printf 'MAKE_TEST_EXIT=%s\n' "$rc" > /tmp/opencode/make-test.exit`.
  A PTY session can be reaped (its buffer disappears from `pty_read`), so the notification's line
  count reflects a partial capture; the marker file survives and is authoritative.
