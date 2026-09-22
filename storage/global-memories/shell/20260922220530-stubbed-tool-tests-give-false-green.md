---
date: 2026-09-22
keywords: ["shell", "bats", "stub", "test", "contract"]
trigger-on: ["stubbed-external-command", "bats-stub-false-green"]
---

## A stubbed external command gives a false green — exercise the real tool once

Two defects in one session passed stub-based BATS tests and were caught only by running the real binary.

`src/agentic/playwright/down.sh` was written as `docker ps -q --filter label=…`, which lists **running** containers only. Every stub-driven test passed; the first real run against a `docker create`d container found nothing and reported "no orphaned containers". The fix was `-aq`, and no stub test could have caught it, because the stub answers `ps` regardless of the flags it is handed — the regression test now asserts the literal `ps -aq --filter …` call shape. Separately, a "contract" test grepped the reaper for the literal `label=dev-bot.mcp=playwright` while the script reaches that value through a `LABEL=` variable, so the assertion was checking a string that never existed and failed on first run.

The rule: a stub proves your *control flow*, not your *interface*. For anything that shells out, assert the exact argument shape the real tool needs, and perform at least one end-to-end invocation against the real binary before trusting the suite (here: `docker create` + reap — cheap and reversible). Green from a stub means "my logic ran", never "the call is correct". A stub that ignores its arguments is the most dangerous kind: it will happily confirm a command that the real tool rejects.
