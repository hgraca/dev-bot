---
date: 2026-10-27
keywords: ["shell", "bats", "flaky-test", "watchdog", "background-job"]
aliases: ["timer pid never logged", "race in teardown test", "orphan process assertion"]
trigger-on: ["background-timer", "process-cleanup-test", "bats-flake"]
---

## A test that asserts a background timer ran must keep the foreground work alive

Asserting "the watchdog timer was started and later reaped" fails intermittently when the guarded command finishes first: the timer subshell can be killed before it writes its pid, so the log is empty and the test fails without any leak having happened. Make the guarded command slow enough (a `git` shim that sleeps on the compared subcommand) that the timer is guaranteed to start, then keep asserting that every recorded pid is gone. A pid-recording `sleep` shim must bake the real binary path at generation time (`exec "$(command -v sleep)"`) or it resolves to itself when the shim dir is first in `PATH`.
