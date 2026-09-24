---
date: 2026-09-24
keywords: ["bats", "harness start.sh", "DEV_BOT_ROOT", "test isolation"]
---

# Harness `start.sh` tests must sandbox `DEV_BOT_ROOT`

## The trap

The "forwards extra args" tests in `src/harnesses/{opencode,claudecode}/tests/start_tests.bats` invoked `start.sh` WITHOUT setting `DEV_BOT_ROOT`, so `_devbot_check_mcp_env_vars` fell back to the real install and scanned the REAL module inventory. Any enabled module whose canonical manifest references an unset `{env:VAR}` then prepends the missing-var warning to stdout — and because those tests assert exact output (`assert_output "--continue"`), they fail. Adding the `sentry` module — the first canonical manifest whose only env ref is a header token — turned both red. They had been latently fragile since the first such module landed: the failure was not about the module under test at all.

## The rule

A launch test that asserts on exact `start.sh` output must point `DEV_BOT_ROOT` at a sandbox root with no enabled modules; the env-gate tests in the same files already did this via a fixture. Asserting against the real inventory couples the test to every module in the repository, so an unrelated module addition can break it.
