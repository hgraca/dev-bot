---
date: 2026-11-02
keywords: ["shell", "bash", "retry", "test-harness"]
aliases: ["assert sleep duration", "backoff test", "stub sleep", "retry test"]
trigger-on: ["bash-retry-test"]
---

## Stub `sleep` to assert a backoff without waiting for it

A retry loop inside a workflow step hardcodes `sleep 30`. Running that step to test it costs a
minute per scenario and makes the suite unusable. Put a `sleep` stub first on `PATH` that appends
its argument to a file and exits 0, then assert the file's contents (`30 30`) — the delay is
verified exactly and the test runs instantly. The production code keeps the literal `30`; no test
hook is added to it.

Pair it with a stub for the command under test, keyed by a per-operation failure counter in a state
directory. Resetting the counter files per scenario lets one stub model transient (fails twice) and
persistent (fails forever) cases, and counting the logged invocations asserts the attempt cap. Then
prove each assertion bites: mutate the workflow copy (drop the retry, drop the warning line, make
one call single-shot) and confirm exactly the matching checks fail.
