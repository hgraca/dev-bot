---
date: 2026-09-11
keywords: ["devbot", "bats", "make", "test", "shell"]
---

# Running dev-bot's full test suite (and BATS directly)

`make test` runs three things in sequence: BATS over `src/` and `bin/` (`BATS_LIB_PATH="$(npm root -g)" bats -T -r src/ bin/`), then `bun test src/`, then a python `unittest` loop over `src/**/test_*.py`. The BATS stage alone ran ~10 minutes (983+ tests, heavy e2e for search-memories, git-report, init scaffold, harness reset), which exceeds a 120s tool timeout. When the command is piped to `tail`, the buffer hides all output until completion, so a timeout shows nothing and looks hung.

Practical invocation:
- Run it backgrounded and poll: `setsid bash -c 'BATS_LIB_PATH="$(npm root -g)" bats -T -r src/ bin/ > /tmp/bats.log 2>&1; echo $? > /tmp/bats.exit' < /dev/null > /dev/null 2>&1 &`, then check `/tmp/bats.exit` and count `^ok `/`^not ok ` in the log.
- Or run the three components separately so a slow BATS run does not mask bun/python.

Invoking a single BATS file directly requires the shared libs on the path or `bats_load_library bats-support`/`bats-assert` fail with "Could not find library": use `BATS_LIB_PATH="$(npm root -g)" bats <file>.bats`. BATS discovers tests recursively, so a new `src/agentic/<mod>/tests/*.bats` is picked up automatically — no manifest to update.
