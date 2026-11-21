---
date: 2026-11-20
keywords: ["shell", "bats", "timeout", "flaky-test", "git-shim"]
aliases: ["second-call test flake", "shared deadline race", "test passes locally fails in CI"]
trigger-on: ["bats-timeout-test", "git-shim-fixture"]
---

## A test that exercises the second call under one deadline must shim the first

When a suite sets a single short cap for every network call (`DEV_BOT_FETCH_TIMEOUT=1`) and then asserts what happens when the *second* call times out, the real first call is running under that same one second. It passes on a developer machine (a local `git fetch` against a file:// remote is milliseconds) and fails on a loaded CI runner, where the same fetch crosses the cap first — so the run reports the fetch's timeout, the assertion about the reset never sees its message, and the test reads as a product bug rather than a fixture race. Shim the earlier call instead of letting it run: `fetch` returns instantly while `reset` sleeps, and the property under test (the second call outlives the deadline) is unchanged. Choose what the fixture must actually decide — here `git ls-remote` still decides "remote moved", and the path validation reads the commit the clone already has, so nothing was lost by short-circuiting the fetch. When a test asserts on a timeout message, check every command that shares the cap, not only the one you are testing.
