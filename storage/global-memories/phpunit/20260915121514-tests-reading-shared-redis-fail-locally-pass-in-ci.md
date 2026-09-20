---
date: 2026-09-15
keywords: ["phpunit", "redis", "test-isolation", "ci", "flaky"]
trigger-on: ["phpunit-shared-external-state", "assert-count-shared-queue"]
---

## Tests asserting absolute counts on shared external state pass in CI and fail locally

A test that writes into a real shared store (Redis queue, shared database table) and asserts the *absolute* size of that store, with no setup or teardown cleanup, is never idempotent: each run leaves its own entry behind, so the second run sees two, and any other application sharing the same instance contributes as well. GitHub Actions hides the defect because every job gets fresh ephemeral services — CI only ever observes "run #1" — while locally, against a long-lived shared Redis, the test fails from the second run onward. Diagnose by inspecting the store directly and comparing the offending entries' timestamps and identifiers: an entry predating the current run proves pollution rather than a production bug. Fix by giving the test's own data a unique value per run (e.g. `Str::uuid()` as a correlation id) and asserting on that filtered subset instead of the total — non-destructive, so it never removes other producers' entries. Resist the tempting shortcut of flushing the shared key in `setUp`, which deletes other applications' in-flight work. Verify by running the suite twice in a row.
