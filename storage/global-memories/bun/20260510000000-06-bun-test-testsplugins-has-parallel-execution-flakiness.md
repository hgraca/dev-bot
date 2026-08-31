---
date: 2026-05-10
keywords: ["bun", "test", "mock"]
---

## `bun test tests/plugins/` has parallel-execution flakiness

Running `bun test tests/plugins/` produces ~40/246 failures across `DiffContextPlugin`, `RememberSessionPlugin`, and `agent-communication` tests when run together — but each test file passes 100% in isolation (`bun test tests/plugins/<file>.test.ts`). The failures look like test-setup races (lock files, watermark files, mocked clients). Symptoms: same expectations fail intermittently, no consistent error pattern across runs. Discovered during the `src/` reorg (commit 2/7) when initially suspected the moves broke imports — but the failures pre-existed the reorg.
Fix/workaround: When verifying changes that touch `src/instructions/plugins/`, run each affected test file in isolation, OR assess the failure count delta rather than absolute. Long-term fix: add `--concurrent=false` or isolate tmp-dir state per test. Tracked in [[memories]] / [[patterns]] for future test-suite hardening.
