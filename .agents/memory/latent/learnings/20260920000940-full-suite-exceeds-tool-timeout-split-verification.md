---
date: 2026-09-20
keywords: ["make-test", "test-runtime", "verification"]
---

# `make test` can exceed a 15-minute timeout — verify in phases

**SUPERSEDED (2026-09-20) by `learnings/20260920164034-01-test-suite-is-io-contention-bound.md` and the rewritten `learnings/20260911160319-devbot-full-test-suite-invocation.md`.** The premise no longer holds: the suite now finishes in ~88 s, the 33 s `update_tests.bats` case was a mock whose orphaned `sleep` held the captured stdout, and that file has since been split into three suites. Run `make test` directly — no phase-splitting, backgrounding or polling is needed.

The parsing gotchas below are still true and worth keeping: `python3 -m unittest <file> | tail -1` can print a blank line for suites whose stdout continues past the summary (`test_search_memories` does), so match `^OK$` / `^FAILED` instead of the last line; and `bats <file>` run alone needs `BATS_LIB_PATH` or every test fails in `setup()`.
