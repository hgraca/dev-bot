---
date: 2026-11-20
keywords: ["shell", "timeout", "exit-code", "watchdog", "bash"]
aliases: ["124 ambiguous", "timeout wrapper status", "watchdog flag"]
trigger-on: ["shell-timeout-wrapper", "git-network-watchdog"]
---

## Exit status 124 cannot prove a watchdog fired — publish the fact instead

A portable timeout wrapper (GNU `timeout` is absent on macOS, so one is hand-rolled) conventionally returns the child's own status when the command finishes and 124 when the deadline expires. The number is therefore ambiguous: a child — a git hook, a wrapper script, a transport — can exit 124 with no timeout at all, and a caller that branches on `rc -eq 124` will report "timed out after 20s" for an ordinary crash. Do not try to reserve another number: any status a child can produce is unsafe. Have the wrapper set a global in the caller's shell — it runs in that shell, so `EXTERNAL_MODULE_TIMED_OUT=1` set on the timeout path is visible after the call — reset it at the start of every call so a stale 1 from an earlier timeout cannot mislabel a later failure, and callers branch on the flag while still reporting the child's real status. Pair it with a test that shims a command exiting 124 by itself and asserts the "failed (exit 124)" wording, not the timeout wording.
