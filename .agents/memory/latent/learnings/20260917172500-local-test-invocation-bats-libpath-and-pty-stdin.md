---
date: 2026-09-17
keywords: ["bats", "make test", "pty", "test invocation"]
---

# Running this repo's test suite outside `make test`

`make test` supplies environment that raw invocations lack — both were hit while running focused tests:

- **BATS needs `BATS_LIB_PATH`.** The Makefile runs `BATS_LIB_PATH="$(npm root -g)" bats -T -r src/ bin/`. Running `bats <file>` directly fails *every* test in `setup()` with `Could not find library 'bats-support' relative to test file or in BATS_LIB_PATH`, which looks like a broken suite rather than a missing env var. Use `BATS_LIB_PATH="$(npm root -g)" bats -T <file>`.
- **`make test` under a PTY needs stdin redirected.** A PTY makes stdin a tty, and this suite branches on `[ -t 0 ]`; run it as `make test </dev/null` or it blocks forever waiting on input that never comes.

Also worth knowing when reading logs: every harness start rotates `.agents/logs/*.log` into `.agents/logs/rotated/<YYYYMMDD>-<name>-<NNN>.log` (`_devbot_rotate_session_logs`), so a log that appears to "reset" across a restart is rotation, not truncation — and evidence you expected to still be there is in `rotated/`.
